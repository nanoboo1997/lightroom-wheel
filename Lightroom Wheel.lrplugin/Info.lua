return {
    LrSdkVersion = 6.0,
    LrSdkMinimumVersion = 6.0,
    LrToolkitIdentifier = 'local.codex.lightroomwheel.bridge',
    LrPluginName = 'Lightroom Wheel Free Bridge',
    LrInitPlugin = 'Init.lua',
    LrForceInitPlugin = true,
    LrLibraryMenuItems = {{title='Start Lightroom Wheel Bridge',file='Start.lua'}},
    LrExportMenuItems = {{title='Start Lightroom Wheel Bridge',file='Start.lua'}},
    LrEnablePlugin = 'Init.lua',
    LrDisablePlugin = 'Shutdown.lua',
    LrShutdownPlugin = 'Shutdown.lua',
    VERSION = {major=0,minor=2,revision=0,build=1},
}
