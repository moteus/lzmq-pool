#include "l52util.h"
#include <assert.h>
#include <errno.h>
#include <memory.h>
#include <stdlib.h>

#if !defined(_WIN32) || defined(USE_PTHREAD)

#include <pthread.h>

#else

#include <windows.h>

#ifndef ETIMEDOUT
#  define ETIMEDOUT WAIT_TIMEOUT
#endif

typedef HANDLE pthread_mutex_t;
typedef HANDLE pthread_cond_t;
typedef void pthread_mutexattr_t;
typedef HANDLE pthread_cond_t;
typedef void pthread_condattr_t;

int pthread_mutex_init(pthread_mutex_t *mutex, const pthread_mutexattr_t *attr){
  assert(attr == NULL);

  *mutex = CreateMutex(NULL, FALSE, NULL);
  if(*mutex == NULL){
    DWORD ret = GetLastError();
    return (ret == 0)? -1 : ret;
  }
  return 0;
}

int pthread_mutex_lock(pthread_mutex_t *mutex){
  DWORD ret = WaitForSingleObject(*mutex, INFINITE);
  if((WAIT_OBJECT_0 == ret) || (WAIT_ABANDONED_0 == ret))
    return 0;
  ret = GetLastError();
  return (ret == 0)? -1 : ret;
}

int pthread_mutex_unlock(pthread_mutex_t *mutex){
  if(TRUE == ReleaseMutex(*mutex))
    return 0;
  else{
    DWORD ret = GetLastError();
    return (ret == 0)? -1 : ret;
  }
}

int pthread_mutex_destroy(pthread_mutex_t *mutex){
  CloseHandle(*mutex);
  *mutex = NULL;
  return 0;
}

int pthread_cond_init(pthread_cond_t *cond, const pthread_condattr_t *attr){
  assert(attr == NULL);
  *cond = CreateEvent(NULL, TRUE, FALSE, NULL);
  if(*cond == NULL){
    DWORD ret = GetLastError();
    return (ret == 0)? -1 : ret;
  }
  return 0;
}

int pthread_cond_wait(pthread_cond_t *cond, pthread_mutex_t *mutex){
  SignalObjectAndWait(*mutex, *cond, INFINITE, FALSE);
  return pthread_mutex_lock(mutex);
}

int pthread_cond_timedwait(pthread_cond_t *cond, pthread_mutex_t *mutex, DWORD timeout){
  DWORD ret = SignalObjectAndWait(*mutex, *cond, timeout, FALSE);
  int rc = pthread_mutex_lock(mutex);
  if(rc != 0) return rc;
  return (ret == WAIT_TIMEOUT)? ETIMEDOUT : 0;
}

int pthread_cond_broadcast(pthread_cond_t *cond){
  if(TRUE == PulseEvent(*cond))
    return 0;
  else{
    DWORD ret = GetLastError();
    return (ret == 0)? -1 : ret;
  }
}

int pthread_cond_destroy(pthread_cond_t *cond){
  CloseHandle(*cond);
  *cond = NULL;
  return 0;
}

#endif

//{ Queue

#define QVOID_LENGTH 255

typedef struct qvoid_tag{
  pthread_cond_t   cond;
  pthread_mutex_t  mutex;
  void            *arr[QVOID_LENGTH];
  int              count;
} qvoid_t;

int qvoid_init(qvoid_t *q){
  memset((void*)q, 0, sizeof(qvoid_t));
  if(0 != pthread_mutex_init(&q->mutex, NULL)){
    return -1;
  }
  if(0 != pthread_cond_init(&q->cond, NULL)){
    pthread_mutex_destroy(&q->mutex);
    return -1;
  }

  return 0;
}

int qvoid_destroy(qvoid_t *q){
  pthread_mutex_destroy(&q->mutex);
  pthread_cond_destroy(&q->cond);
  memset((void*)q, 0, sizeof(qvoid_t));
  return 0;
}

int qvoid_capacity(qvoid_t *q){
  return QVOID_LENGTH;
}

int qvoid_size(qvoid_t *q){
  return q->count;
}

int qvoid_empty(qvoid_t *q){
  return qvoid_size(q) == 0;
}

int qvoid_full(qvoid_t *q){
  return qvoid_size(q) == qvoid_capacity(0);
}

int qvoid_put(qvoid_t *q, void *data){
  int ret = pthread_mutex_lock(&q->mutex);
  if(ret != 0) return ret;
  while(qvoid_full(q)){
    ret = pthread_cond_wait(&q->cond, &q->mutex);
    if(ret != 0) return ret;
  }

  q->arr[q->count++] = data;
  assert(q->count <= QVOID_LENGTH);

  pthread_cond_broadcast(&q->cond);
  pthread_mutex_unlock(&q->mutex);
  return 0;
}

int qvoid_get(qvoid_t *q, void **data){
  int ret = pthread_mutex_lock(&q->mutex);
  if(ret != 0) return ret;
  while(qvoid_empty(q)){
    ret = pthread_cond_wait(&q->cond, &q->mutex);
    if(ret != 0) return ret;
  }

  assert(q->count > 0);
  *data = q->arr[--q->count];

  pthread_cond_broadcast(&q->cond);
  pthread_mutex_unlock(&q->mutex);
  return 0;
}

//}

//{ Lua interface

static volatile size_t s_queue_size = 0;
static qvoid_t *s_queue = NULL;

static int pool_init(lua_State *L){
  int n = luaL_checkint(L, 1);
  luaL_argcheck(L, n > 0, 1, "must be positive");
  if(!s_queue){
    int i;
    s_queue = (qvoid_t*)malloc(n * sizeof(qvoid_t));
    if(!s_queue) return -1;
    for(i = 0; i < n; ++i){
      if(0 != qvoid_init(&s_queue[i])){
        while(--i >= 0){
          qvoid_destroy(&s_queue[i]);
        }
        free(s_queue);
        s_queue = NULL;
        return -1;
      }
    }
    s_queue_size = n;
  }
  lua_pushnumber(L, 0);
  return 1;
}

static qvoid_t* pool_at(lua_State *L, int idx){
  int i = luaL_checkint(L, idx);
  luaL_argcheck(L, (i >= 0)&&((size_t)i < s_queue_size), idx, "index out of range");
  return &s_queue[i];
}

static int pool_put(lua_State *L){
  qvoid_t *q = pool_at(L, 1);
  void *data = lua_touserdata(L, 2);

  luaL_argcheck(L, data && lua_islightuserdata(L, 2), 2, "lightuserdata expected");

  lua_pushnumber(L, qvoid_put(q, data));
  return 1;
}

static int pool_get(lua_State *L){
  qvoid_t *q = pool_at(L, 1);
  void *data;
  int rc = qvoid_get(q, &data);
  if(rc == 0)lua_pushlightuserdata(L, data);
  else lua_pushnumber(L, rc);
  return 1;
}

static int pool_capacity(lua_State *L){
  qvoid_t *q = pool_at(L, 1);
  lua_pushnumber(L, qvoid_capacity(q));
  return 1;
}

static int pool_size(lua_State *L){
  qvoid_t *q = pool_at(L, 1);
  lua_pushnumber(L, qvoid_capacity(q));
  return 1;
}

static int pool_close(lua_State *L){
  if(s_queue){
    int i = s_queue_size;
    while(--i >= 0){
      qvoid_destroy(&s_queue[i]);
    }
    free(s_queue);
    s_queue = NULL;
    s_queue_size = 0;
  }

  lua_pushnumber(L, 0);
  return 1;
}

static const struct luaL_Reg l_pool_lib[] = {
  { "init",      pool_init        },
  { "put",       pool_put         },
  { "get",       pool_get         },
  { "capacity",  pool_capacity    },
  { "size",      pool_size        },
  { "close",     pool_close       },
  {NULL, NULL}
};

//}

int luaopen_lzmq_pool_core(lua_State *L){
  lua_newtable(L);
  luaL_setfuncs(L, l_pool_lib, 0);
  return 1;
}


