os.setlocale("")
package.path = BOOT.plugin_dir .. "/?.yazi/init.lua;" .. package.path

require("dds"):setup()
require("archive"):setup()
