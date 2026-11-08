#!/usr/bin/env python3
"""Generate the iPad project with references to the authoritative shared sources."""
from pathlib import Path
import hashlib, json, plistlib
root = Path(__file__).resolve().parent
objects = {}
def obj(key, **values):
    ident = hashlib.sha1(key.encode()).hexdigest()[:24].upper()
    objects[ident] = values
    return ident
def file(path, kind):
    return obj('file:'+path, isa='PBXFileReference', lastKnownFileType=kind, path=path, sourceTree='<group>')
def phase(key, isa, refs):
    return obj(key, isa=isa, buildActionMask=2147483647, files=[obj('build:'+key+ref,isa='PBXBuildFile',fileRef=ref) for ref in refs], runOnlyForDeploymentPostprocessing=0)
shared = ['OGSModels','OGSScoringState','SGFPlayerEngine','AppSettings','AIModels','LocalScoring','StoneJitter','SceneManager3D','TatamiTexture','GoEquipment3D','ShojiEnvironment','GardenScenery','EnvironmentMaterials','PlayingEnvironment','KayaFloorBoard']
sources = [file('../SGFPlayerClean/Models/'+name+'.swift','sourcecode.swift') for name in shared]
sources += [file('../'+str(p.relative_to(root.parent)),'sourcecode.swift') for p in sorted((root.parent/'SGFPlayerClean/Services/Networking').glob('*.swift'))]
sources += [file('../SGFPlayerClean/'+p,'sourcecode.swift') for p in ['Services/OGSClient.swift','ViewModels/OGSGameViewModel.swift','ViewModels/TimeControlManager.swift']]
sources += [file(str(p.relative_to(root)),'sourcecode.swift') for p in sorted((root/'Sources').glob('*.swift'))]
assets=root.parent/'SGFPlayerClean/Assets'
resources=[file('Assets.xcassets','folder.assetcatalog'),file('KataGo/Licenses','folder'),file('../SGFPlayerClean/Resources/kata1-b18.bin.gz','file'),file('../SGFPlayerClean/Models/BowlLayouts.json','text.json'), file('../SGFPlayerClean/Assets/Environments','folder')]
resources += [file('../'+str(p.relative_to(root.parent)), 'file') for p in sorted(assets.rglob('*')) if p.is_file() and 'Environments' not in p.parts and p.suffix.lower() in ['.png','.jpg','.mp3','.aiff']]
signing_ref = file('Signing.local.xcconfig','text.xcconfig') if (root/'Signing.local.xcconfig').exists() else None
product=obj('product',isa='PBXFileReference',explicitFileType='wrapper.application',path='QuietGo-iPad.app',sourceTree='BUILT_PRODUCTS_DIR')
products=obj('products',isa='PBXGroup',children=[product],name='Products',sourceTree='<group>')
group=obj('group',isa='PBXGroup',children=sources+resources+[products]+([signing_ref] if signing_ref else []),sourceTree='<group>')
def configs(key,settings):
    refs=[]
    for name in ['Debug','Release']:
        s=dict(settings)
        s['SWIFT_OPTIMIZATION_LEVEL']='-Onone' if name=='Debug' else '-O'
        if name=='Debug': s['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
        extra = {'baseConfigurationReference': signing_ref} if key=='projectconfig' and signing_ref else {}
        refs.append(obj(key+name,isa='XCBuildConfiguration',buildSettings=s,name=name,**extra))
    return obj(key+'list',isa='XCConfigurationList',buildConfigurations=refs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
settings=dict(ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon', SWIFT_OBJC_BRIDGING_HEADER='KataGo/QuietKataGo.h', LIBRARY_SEARCH_PATHS=['$(inherited)','$(PROJECT_DIR)/.build/katago-$(PLATFORM_NAME)'], OTHER_LDFLAGS=['-lQuietKataGo','-lc++','-lz'], PRODUCT_BUNDLE_IDENTIFIER='com.davemarvit.QuietGo.iPad',PRODUCT_NAME='QuietGo-iPad',SWIFT_VERSION='5.0',IPHONEOS_DEPLOYMENT_TARGET='17.0',TARGETED_DEVICE_FAMILY='2',SDKROOT='iphoneos',SUPPORTED_PLATFORMS='iphoneos iphonesimulator',SUPPORTS_MACCATALYST='NO',INFOPLIST_FILE='Info.plist',CODE_SIGN_STYLE='Automatic',ENABLE_USER_SCRIPT_SANDBOXING='YES',SWIFT_EMIT_LOC_STRINGS='YES')
target=obj('target',isa='PBXNativeTarget',buildConfigurationList=configs('targetconfig',settings),buildPhases=[phase('sources','PBXSourcesBuildPhase',sources),phase('resources','PBXResourcesBuildPhase',resources)],buildRules=[],dependencies=[],name='QuietGo-iPad',productName='QuietGo-iPad',productReference=product,productType='com.apple.product-type.application')
test_targets=[]
for name, folder, ui in [('TabletTests','Tests',False),('TabletUITests','UITests',True)]:
    tests=[file(str(p.relative_to(root)),'sourcecode.swift') for p in sorted((root/folder).glob('*.swift'))]
    prod=obj(name+'product',isa='PBXFileReference',explicitFileType='wrapper.cfbundle',path=name+'.xctest',sourceTree='BUILT_PRODUCTS_DIR')
    objects[products]['children'].append(prod); objects[group]['children'] += tests
    ts=dict(PRODUCT_BUNDLE_IDENTIFIER='com.davemarvit.QuietGo.'+name,PRODUCT_NAME=name,SWIFT_VERSION='5.0',IPHONEOS_DEPLOYMENT_TARGET='17.0',TARGETED_DEVICE_FAMILY='2',SDKROOT='iphoneos',GENERATE_INFOPLIST_FILE='YES',CODE_SIGN_STYLE='Automatic')
    if ui: ts['TEST_TARGET_NAME']='QuietGo-iPad'
    else:
        ts['TEST_HOST']='$(BUILT_PRODUCTS_DIR)/QuietGo-iPad.app/QuietGo-iPad'
        ts['BUNDLE_LOADER']='$(TEST_HOST)'
    dep=obj(name+'dependency',isa='PBXTargetDependency',target=target)
    t=obj(name,isa='PBXNativeTarget',buildConfigurationList=configs(name+'config',ts),buildPhases=[phase(name+'sources','PBXSourcesBuildPhase',tests)],buildRules=[],dependencies=[dep],name=name,productName=name,productReference=prod,productType='com.apple.product-type.bundle.'+('ui-testing' if ui else 'unit-test'))
    test_targets.append((name,t))
project=obj('project' ,isa='PBXProject',attributes={'LastUpgradeCheck':'2630'},buildConfigurationList=configs('projectconfig',{'CLANG_ENABLE_MODULES':'YES','ENABLE_TESTABILITY':'YES','ARCHS':'arm64','ONLY_ACTIVE_ARCH':'YES'}),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[target]+[t for _,t in test_targets])
def encode(x,depth=0):
    if isinstance(x,dict): return '{\n'+''.join('\t'*(depth+1)+json.dumps(k)+' = '+encode(v,depth+1)+';\n' for k,v in x.items())+'\t'*depth+'}'
    if isinstance(x,list): return '('+', '.join(encode(v,depth) for v in x)+')'
    return str(x) if isinstance(x,int) else json.dumps(x)
p=root/'QuietGo-iPad.xcodeproj';p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode(dict(archiveVersion=1,classes={},objectVersion=56,objects=objects,rootObject=project))+'\n')
print(p)

scheme=p/'xcshareddata/xcschemes'; scheme.mkdir(parents=True,exist_ok=True)
def reference(name, ident, product):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:QuietGo-iPad.xcodeproj"/>'
app=reference('QuietGo-iPad',target,'QuietGo-iPad.app')
entries=''.join('<TestableReference skipped="NO">'+reference(n,t,n+'.xctest')+'</TestableReference>' for n,t in test_targets)
(scheme/'QuietGo-iPad.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2630" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>{entries}</Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
