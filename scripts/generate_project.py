#!/usr/bin/env python3
"""Regenerate a dependency-free Xcode project from the checked-in Swift sources."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / 'Podhod.xcodeproj'
PROJECT.mkdir(exist_ok=True)

def uid(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()

def q(value):
    return json.dumps(str(value), ensure_ascii=False)

objects = []
def obj(key, body):
    objects.append(f'\t\t{uid(key)} = {{ {body} }};')
    return uid(key)

def refs(values):
    return '(' + ', '.join(values) + (',' if values else '') + ')'

files = {}
app_sources = sorted((ROOT / 'Podhod').rglob('*.swift'))
unit_sources = sorted((ROOT / 'PodhodTests').glob('*.swift'))
ui_sources = sorted((ROOT / 'PodhodUITests').glob('*.swift'))
assets = ROOT / 'Podhod/Resources/Assets.xcassets'
other = [ROOT / 'Podhod/Resources/Info.plist', ROOT / 'Podhod/Resources/Podhod.entitlements', assets]
for path in app_sources + unit_sources + ui_sources + other:
    rel = str(path.relative_to(ROOT))
    kind = 'sourcecode.swift' if path.suffix == '.swift' else 'folder.assetcatalog' if path.suffix == '.xcassets' else 'text.plist.xml'
    files[rel] = obj('file:' + rel, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {q(rel)}; sourceTree = "<group>";')

products = {}
for name, suffix, kind in [('Podhod', 'app', 'wrapper.application'), ('PodhodTests', 'xctest', 'wrapper.cfbundle'), ('PodhodUITests', 'xctest', 'wrapper.cfbundle')]:
    products[name] = obj('product:' + name, f'isa = PBXFileReference; explicitFileType = {kind}; path = {name}.{suffix}; sourceTree = BUILT_PRODUCTS_DIR;')

app_group = obj('group:app', f'isa = PBXGroup; name = "Подход"; children = {refs([files[str(p.relative_to(ROOT))] for p in app_sources + other])}; sourceTree = "<group>";')
test_group = obj('group:tests', f'isa = PBXGroup; name = Tests; children = {refs([files[str(p.relative_to(ROOT))] for p in unit_sources + ui_sources])}; sourceTree = "<group>";')
product_group = obj('group:products', f'isa = PBXGroup; name = Products; children = {refs(list(products.values()))}; sourceTree = "<group>";')
main_group = obj('group:main', f'isa = PBXGroup; children = {refs([app_group, test_group, product_group])}; sourceTree = "<group>";')

def settings_text(settings):
    return '{ ' + ' '.join(f'{key} = {q(value)};' for key, value in settings.items()) + ' }'

project_configs = []
for config in ['Debug', 'Release']:
    settings = {
        'ALWAYS_SEARCH_USER_PATHS': 'NO', 'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES',
        'CLANG_WARN_DOCUMENTATION_COMMENTS': 'YES', 'CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER': 'YES',
        'GCC_C_LANGUAGE_STANDARD': 'gnu17', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0',
        'SDKROOT': 'iphoneos', 'SWIFT_VERSION': '5.0', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES',
        'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if config == 'Debug' else '-O',
        'DEBUG_INFORMATION_FORMAT': 'dwarf' if config == 'Debug' else 'dwarf-with-dsym',
        'ENABLE_TESTABILITY': 'YES' if config == 'Debug' else 'NO',
        'ONLY_ACTIVE_ARCH': 'YES' if config == 'Debug' else 'NO',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG $(inherited)' if config == 'Debug' else '$(inherited)',
    }
    project_configs.append(obj('projectconfig:' + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {settings_text(settings)};'))
project_config_list = obj('configlist:project', f'isa = XCConfigurationList; buildConfigurations = {refs(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

targets = []
for name, source_paths in [('Podhod', app_sources), ('PodhodTests', unit_sources), ('PodhodUITests', ui_sources)]:
    source_builds = []
    for path in source_paths:
        rel = str(path.relative_to(ROOT))
        source_builds.append(obj('build:' + name + ':' + rel, f'isa = PBXBuildFile; fileRef = {files[rel]};'))
    source_phase = obj('sources:' + name, f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(source_builds)}; runOnlyForDeploymentPostprocessing = 0;')
    resources = []
    if name == 'Podhod':
        resources.append(obj('build:assets', f'isa = PBXBuildFile; fileRef = {files[str(assets.relative_to(ROOT))]};'))
    resource_phase = obj('resources:' + name, f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {refs(resources)}; runOnlyForDeploymentPostprocessing = 0;')
    framework_phase = obj('frameworks:' + name, 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    target_configs = []
    for config in ['Debug', 'Release']:
        settings = {
            'PRODUCT_NAME': '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER': 'app.personal.' + name.lower(),
            'TARGETED_DEVICE_FAMILY': '1', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator',
            'SUPPORTS_MACCATALYST': 'NO', 'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD': 'NO',
            'CODE_SIGN_STYLE': 'Automatic', 'CURRENT_PROJECT_VERSION': '2', 'MARKETING_VERSION': '1.1',
            'SWIFT_VERSION': '5.0', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks',
            'GENERATE_INFOPLIST_FILE': 'YES',
        }
        if name == 'Podhod':
            settings.update({
                'GENERATE_INFOPLIST_FILE': 'NO', 'INFOPLIST_FILE': 'Podhod/Resources/Info.plist',
                'CODE_SIGN_ENTITLEMENTS': 'Podhod/Resources/Podhod.entitlements',
                'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME': 'AccentColor',
                'ENABLE_PREVIEWS': 'YES', 'SWIFT_EMIT_LOC_STRINGS': 'YES',
            })
        elif name == 'PodhodTests':
            settings.update({'BUNDLE_LOADER': '$(TEST_HOST)', 'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/Podhod.app/Podhod'})
        else:
            settings.update({'TEST_TARGET_NAME': 'Podhod'})
        target_configs.append(obj('targetconfig:' + name + ':' + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {settings_text(settings)};'))
    config_list = obj('configlist:' + name, f'isa = XCConfigurationList; buildConfigurations = {refs(target_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    dependencies = []
    if name != 'Podhod':
        proxy = obj('proxy:' + name, f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("target:Podhod")}; remoteInfo = Podhod;')
        dependencies.append(obj('dependency:' + name, f'isa = PBXTargetDependency; target = {uid("target:Podhod")}; targetProxy = {proxy};'))
    product_type = 'com.apple.product-type.application' if name == 'Podhod' else 'com.apple.product-type.bundle.unit-test' if name == 'PodhodTests' else 'com.apple.product-type.bundle.ui-testing'
    targets.append(obj('target:' + name, f'isa = PBXNativeTarget; buildConfigurationList = {config_list}; buildPhases = {refs([source_phase, framework_phase, resource_phase])}; buildRules = (); dependencies = {refs(dependencies)}; name = {name}; productName = {name}; productReference = {products[name]}; productType = {q(product_type)};'))

obj('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 2600; LastUpgradeCheck = 2600; TargetAttributes = {{ {uid("target:Podhod")} = {{ CreatedOnToolsVersion = 26.6; SystemCapabilities = {{ com.apple.HealthKit = {{ enabled = 1; }}; }}; }}; }}; }}; buildConfigurationList = {project_config_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ru; hasScannedForEncodings = 0; knownRegions = (ru, en, Base); mainGroup = {main_group}; productRefGroup = {product_group}; projectDirPath = ""; projectRoot = ""; targets = {refs(targets)};')
content = '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + '\n\t};\n\trootObject = ' + uid('project') + ';\n}\n'
(PROJECT / 'project.pbxproj').write_text(content)

scheme_dir = PROJECT / 'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
def build_ref(name):
    ext = 'app' if name == 'Podhod' else 'xctest'
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target:"+name)}" BuildableName="{name}.{ext}" BlueprintName="{name}" ReferencedContainer="container:Podhod.xcodeproj"/>'
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{build_ref('Podhod')}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{build_ref('PodhodTests')}</TestableReference><TestableReference skipped="NO">{build_ref('PodhodUITests')}</TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{build_ref('Podhod')}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugServiceExtension="internal"><BuildableProductRunnable runnableDebuggingMode="0">{build_ref('Podhod')}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(scheme_dir / 'Podhod.xcscheme').write_text(scheme)
print(f'Generated {PROJECT}: {len(app_sources)} app files, {len(unit_sources)} unit test files, {len(ui_sources)} UI test files.')
