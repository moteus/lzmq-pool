package = "lzmq-pool"
version = "scm-0"

source = {
  url = "https://github.com/moteus/lzmq-pool/archive/master.zip",
  dir = "lzmq-pool-master",
}

description = {
  summary = "ZMQ socket pool",
  homepage = "https://github.com/moteus/lzmq-pool",
  license = "MIT/X11",
}

dependencies = {
  "lua >= 5.1, < 5.3",
  -- "lzmq > 3.1" or "lzmq-ffi > 3.1",
}

build = {
  copy_directories = {"test", "examples"},

  type = "builtin",

  platforms = {
    unix    = { modules = {
      ["lzmq.pool.core"] = {
        libraries = {"pthread"},
      }
    }},

    -- mingw32  = { modules = {
    --   ["lzmq.pool.core"] = {
    --     libraries = {"pthread"},
    --     defines   = {"USE_PTHREAD"},
    --   }
    -- }},
  },

  modules = {
    ["lzmq.pool.core" ] = {
      sources = {'src/l52util.c','src/q.c'},
    },
    ["lzmq.pool"      ] = "src/lua/pool.lua";
  },
}
