#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <stdexcept>
#include <string_view>

#ifndef WAYNERGY_CURSOR_BUILD_HASH
#define WAYNERGY_CURSOR_BUILD_HASH GIT_COMMIT_HASH
#endif

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    const auto runtimeCommit = HyprlandAPI::getHyprlandVersion(handle).hash;
    const auto runtimeABI = std::string(__hyprland_api_get_hash());
    // The header's inline helper owns process-unique static strings that can
    // outlive a plugin unload. Build a fresh fingerprint for every load.
    const auto majorMinor = [](std::string_view version) {
        return std::string(version.substr(0, version.find_last_of('.')));
    };
    const auto buildABI = std::string(GIT_COMMIT_HASH) + "_aq_" + majorMinor(AQUAMARINE_VERSION) +
        "_hu_" + majorMinor(HYPRUTILS_VERSION) + "_hg_" + majorMinor(HYPRGRAPHICS_VERSION) +
        "_hc_" + majorMinor(HYPRCURSOR_VERSION) + "_hlg_" + majorMinor(HYPRLANG_VERSION);
    if (runtimeCommit != WAYNERGY_CURSOR_BUILD_HASH || runtimeABI != buildABI)
        throw std::runtime_error("Waynergy cursor plugin: Hyprland header/runtime ABI mismatch (runtime=" + runtimeABI +
                                 ", build=" + buildABI + "); rerun install-cursor-sync.sh");

    if (!HyprlandAPI::addLuaFunction(handle, "waynergy", "refresh_cursor", [](lua_State*) -> int {
            g_pHyprRenderer->ensureCursorRenderingMode();
            return 0;
        }))
        throw std::runtime_error("Waynergy cursor plugin: cannot register Lua callback");

    return {"waynergy-cursor-refresh", "Apply cursor visibility without the renderer timer", "sgu11", "1.0"};
}
