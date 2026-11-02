#!/usr/bin/env python3
"""Deterministic iPhone + watchOS companion project; local signing stays ignored."""
from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[1]
def uid(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
objects=[]
def obj(key,body):
    objects.append(f'{uid(key)} = {{ {body} }};'); return uid(key)
common=['Shared/DashboardSnapshot.swift','Shared/Localization.swift','Shared/WatchTransfer.swift','Shared/ConnectivityCallbacks.swift']
def swift(folder): return [str(p.relative_to(root)) for p in sorted((root/folder).glob('*.swift'))]
targets={
 'app':dict(name='OpenIntake',bundle='$(OPENINTAKE_BUNDLE_ID)',folder='App',sdk='iphoneos',files=swift('App')+swift('Sources/IntakeCore')+swift('Shared'),ext=False,deps=['widgets','watch']),
 'widgets':dict(name='OpenIntakeWidgets',bundle='$(OPENINTAKE_BUNDLE_ID).widgets',folder='Widgets',sdk='iphoneos',files=swift('Widgets')+swift('Shared'),ext=True,deps=[]),
 'watch':dict(name='OpenIntakeWatch',bundle='$(OPENINTAKE_BUNDLE_ID).watchkitapp',folder='WatchApp',sdk='watchos',files=swift('WatchApp')+common,ext=False,deps=['complications']),
 'complications':dict(name='OpenIntakeComplications',bundle='$(OPENINTAKE_BUNDLE_ID).watchkitapp.complications',folder='WatchWidgets',sdk='watchos',files=swift('WatchWidgets')+common,ext=True,deps=[])
}
refs={}
for path in sorted({p for t in targets.values() for p in t['files']}):
 refs[path]=obj('ref'+path,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path}"; sourceTree = SOURCE_ROOT;')
config=obj('config','isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Config/App.xcconfig; sourceTree = SOURCE_ROOT;')
resource_refs=[]
for table in ['Localizable','InfoPlist']:
 children=[]
 for lang in ['en','zh-Hans']:
  path=f'Shared/Resources/{lang}.lproj/{table}.strings'
  if not (root/path).exists(): continue
  children.append(obj('res'+path,f'isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = "{lang}"; path = "{path}"; sourceTree = SOURCE_ROOT;'))
 if children: resource_refs.append(obj('variant'+table,f'isa = PBXVariantGroup; children = ({",".join(children)}); name = "{table}.strings"; sourceTree = "<group>";'))
privacy=obj('privacy','isa = PBXFileReference; lastKnownFileType = text.xml; path = App/PrivacyInfo.xcprivacy; sourceTree = SOURCE_ROOT;')
assets=obj('assets','isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = App/Assets.xcassets; sourceTree = SOURCE_ROOT;')
fooddb=obj('fooddb','isa = PBXFileReference; lastKnownFileType = file; path = Sources/IntakeCore/Resources/FoodReference.sqlite; sourceTree = SOURCE_ROOT;')
watchassets=obj('watchassets','isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = WatchApp/Assets.xcassets; sourceTree = SOURCE_ROOT;')
products=[]
for key,t in targets.items():
 extension='appex' if t['ext'] else 'app'
 t['product']=obj(key+'product',f'isa = PBXFileReference; explicitFileType = "wrapper.{"app-extension" if t["ext"] else "application"}"; path = "{t["name"]}.{extension}"; sourceTree = BUILT_PRODUCTS_DIR;')
 products.append(t['product'])
productgroup=obj('products',f'isa = PBXGroup; children = ({",".join(products)}); name = Products; sourceTree = "<group>";')
obj('group',f'isa = PBXGroup; children = ({",".join(list(refs.values())+[config,privacy,assets,watchassets,fooddb]+resource_refs+[productgroup])}); sourceTree = "<group>";')
for key,t in targets.items():
 builds=[obj(key+p,f'isa = PBXBuildFile; fileRef = {refs[p]};') for p in t['files']]
 sources=obj(key+'sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)}); runOnlyForDeploymentPostprocessing = 0;')
 resourcebuilds=[obj(key+'res'+r,f'isa = PBXBuildFile; fileRef = {r};') for r in resource_refs+[privacy]+([assets,fooddb] if key=='app' else [watchassets] if key=='watch' else [])]
 resources=obj(key+'resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resourcebuilds)}); runOnlyForDeploymentPostprocessing = 0;')
 frameworks=obj(key+'frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
 phases=[sources,frameworks,resources];dependencies=[]
 for dep in t['deps']:
  proxy=obj(key+dep+'proxy',f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid(dep+"target")}; remoteInfo = {targets[dep]["name"]};')
  dependencies.append(obj(key+dep+'dependency',f'isa = PBXTargetDependency; target = {uid(dep+"target")}; targetProxy = {proxy};'))
  build=obj(key+dep+'embedbuild',f'isa = PBXBuildFile; fileRef = {targets[dep]["product"]}; settings = {{ ATTRIBUTES = (RemoveHeadersOnCopy); }};')
  dest='dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"; dstSubfolderSpec = 16;' if dep=='watch' else 'dstPath = ""; dstSubfolderSpec = 13;'
  phases.append(obj(key+dep+'embed',f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; {dest} files = ({build}); name = "Embed {targets[dep]["name"]}"; runOnlyForDeploymentPostprocessing = 0;'))
 configs=[]
 for mode in ['Debug','Release']:
  watch=t['sdk']=='watchos'
  settings=f'PRODUCT_NAME = {t["name"]}; PRODUCT_BUNDLE_IDENTIFIER = "{t["bundle"]}"; SDKROOT = {t["sdk"]}; SWIFT_VERSION = 6.0; CLANG_ENABLE_MODULES = YES; '
  settings+=('WATCHOS_DEPLOYMENT_TARGET = 10.0; TARGETED_DEVICE_FAMILY = 4; SUPPORTED_PLATFORMS = "watchos watchsimulator"; ' if watch else 'IPHONEOS_DEPLOYMENT_TARGET = 17.0; TARGETED_DEVICE_FAMILY = 1; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; ')
  ent=f'{t["folder"]}/OpenIntake.entitlements' if key!='widgets' else 'Widgets/OpenIntakeWidgets.entitlements'
  settings+=f'GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = {t["folder"]}/Info.plist; CODE_SIGN_ENTITLEMENTS = {ent}; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 20; MARKETING_VERSION = 0.8.0; SWIFT_STRICT_CONCURRENCY = complete; '
  if t['ext']: settings+='APPLICATION_EXTENSION_API_ONLY = YES; SKIP_INSTALL = YES; '
  if key=='watch': settings+='SKIP_INSTALL = YES; '
  if key in ['app','watch']: settings+='ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; '
  conditions=('DEBUG ' if mode=='Debug' else '')+('WIDGET_EXTENSION' if t['ext'] else '')
  settings+=f'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "{conditions}"; SWIFT_OPTIMIZATION_LEVEL = "{"-Onone" if mode=="Debug" else "-O"}";'
  configs.append(obj(key+mode,f'isa = XCBuildConfiguration; baseConfigurationReference = {config}; buildSettings = {{ {settings} }}; name = {mode};'))
 conf=obj(key+'configs',f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
 kind='app-extension' if t['ext'] else 'application'
 obj(key+'target',f'isa = PBXNativeTarget; buildConfigurationList = {conf}; buildPhases = ({",".join(phases)}); buildRules = (); dependencies = ({",".join(dependencies)}); name = {t["name"]}; productName = {t["name"]}; productReference = {t["product"]}; productType = "com.apple.product-type.{kind}";')
configs=[obj('project'+mode,f'isa = XCBuildConfiguration; buildSettings = {{ }}; name = {mode};') for mode in ['Debug','Release']]
obj('projectconfigs',f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base, "zh-Hans"); mainGroup = {uid("group")}; productRefGroup = {productgroup}; projectDirPath = ""; projectRoot = ""; targets = ({",".join(uid(k+"target") for k in targets)});')
project=root/'OpenIntake.xcodeproj';project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {uid("project")}; }}\n')
folder=project/'xcshareddata/xcschemes';folder.mkdir(parents=True,exist_ok=True)
scheme_template=(root/'scripts/scheme.template.xml').read_text()
for key in ['app','watch']:
 name=targets[key]['name']
 (folder/(name+'.xcscheme')).write_text(scheme_template.replace('__TARGET_ID__',uid(key+'target')).replace('__TARGET_NAME__',name))
