{ version }:
{
  CFBundleDevelopmentRegion = "en";
  CFBundleExecutable = "warp-oss";
  CFBundleIdentifier = "dev.warp.WarpOss";
  CFBundleInfoDictionaryVersion = "6.0";
  CFBundleName = "WarpOss";
  CFBundleDisplayName = "WarpOss";
  CFBundlePackageType = "APPL";
  CFBundleShortVersionString = version;
  CFBundleVersion = "1";
  CFBundleIconFile = "AppIcon";
  LSApplicationCategoryType = "public.app-category.developer-tools";
  LSMinimumSystemVersion = "10.14";
  NSHighResolutionCapable = true;
  NSPrincipalClass = "NSApplication";
  NSDockTilePlugIn = "WarpDockTilePlugin.docktileplugin";
  CFBundleURLTypes = [
    {
      CFBundleURLName = "WarpOss URL";
      CFBundleURLSchemes = [ "warposs" ];
    }
  ];
}
