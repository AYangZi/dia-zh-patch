#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

static NSMutableDictionary<NSString *, NSValue *> *
  DiaZhSetTitleImplementations;
static NSMutableDictionary<NSString *, NSValue *> *
  DiaZhSetAttributedTitleImplementations;
static NSMutableDictionary<NSString *, NSValue *> *
  DiaZhTitleImplementations;
static NSMutableDictionary<NSString *, NSValue *> *
  DiaZhAttributedTitleImplementations;

static IMP DiaZhOriginalImplementation(
  id object,
  NSMutableDictionary<NSString *, NSValue *> *implementations
);

// Shared across the four accessors: an original implementation can call super,
// another accessor, or another menu item's title while resolving its value.
static __thread NSUInteger DiaZhMenuTranslationDepth;

static NSString *DiaZhUntranslatedTitle(NSMenuItem *item) {
  ++DiaZhMenuTranslationDepth;
  @try {
    IMP original = DiaZhOriginalImplementation(item, DiaZhTitleImplementations);
    return original
      ? ((NSString *(*)(id, SEL))original)(item, @selector(title)) : item.title;
  } @finally {
    --DiaZhMenuTranslationDepth;
  }
}

static NSString *DiaZhResourcePath(NSString *name) {
  NSString *override = NSProcessInfo.processInfo.environment[
    @"DIA_ZH_RESOURCE_ROOT"
  ];
  NSString *root = override.length > 0
    ? override
    : [NSBundle.mainBundle.resourcePath
        stringByAppendingPathComponent:@"DiaZhPatch"];
  return [root stringByAppendingPathComponent:name];
}

static NSDictionary<NSString *, NSString *> *DiaZhTranslations(void) {
  static NSDictionary<NSString *, NSString *> *translations;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSString *path = DiaZhResourcePath(@"zh-Hans.strings");
    NSDictionary *catalog = [NSDictionary dictionaryWithContentsOfFile:path];
    translations = [catalog isKindOfClass:NSDictionary.class] ? catalog : @{};
  });
  return translations;
}

static NSSet<NSString *> *DiaZhMenuKeys(void) {
  static NSSet<NSString *> *keys;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSString *path = DiaZhResourcePath(@"menu-keys.txt");
    NSString *contents = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
    NSMutableSet *loaded = NSMutableSet.set;
    for (NSString *line in [contents componentsSeparatedByCharactersInSet:
      NSCharacterSet.newlineCharacterSet]) {
      NSString *key = [line stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if (key.length > 0 && ![key hasPrefix:@"#"]) {
        [loaded addObject:key];
      }
    }
    keys = loaded.copy;
  });
  return keys;
}

static NSString *DiaZhNormalizedSource(NSString *source) {
  if (![source isKindOfClass:NSString.class] || source.length == 0) {
    return nil;
  }

  NSMutableCharacterSet *padding =
    NSCharacterSet.whitespaceAndNewlineCharacterSet.mutableCopy;
  [padding addCharactersInString:
    @"\u200B\u200C\u200D\u200E\u200F\u202A\u202B\u202C\u202D\u202E\u2060\u2066\u2067\u2068\u2069\uFEFF"];
  NSString *normalized = [source stringByTrimmingCharactersInSet:padding];
  NSRange tab = [normalized rangeOfString:@"\t"];
  if (tab.location != NSNotFound) {
    normalized = [normalized substringToIndex:tab.location];
  }
  return normalized;
}

static NSString *DiaZhSourceForTitle(NSString *title) {
  NSString *normalized = DiaZhNormalizedSource(title);
  if (!normalized) {
    return nil;
  }
  if ([DiaZhMenuKeys() containsObject:normalized]) {
    return normalized;
  }

  // Menu getters run repeatedly during AppKit layout. Build the reverse map
  // once instead of walking the entire catalog for every view property.
  static NSDictionary<NSString *, NSString *> *sources;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSMutableDictionary *loaded = NSMutableDictionary.dictionary;
    [DiaZhTranslations() enumerateKeysAndObjectsUsingBlock:
      ^(NSString *key, NSString *value, __unused BOOL *stop) {
        if ([DiaZhMenuKeys() containsObject:key] && !loaded[value]) {
          loaded[value] = key;
        }
      }];
    sources = loaded.copy;
  });
  return sources[normalized];
}

static NSString *DiaZhRootMenuSource(NSMenuItem *item) {
  NSMenu *menu = item.menu;
  if (!menu) {
    return nil;
  }

  while (menu.supermenu && menu.supermenu != NSApp.mainMenu) {
    menu = menu.supermenu;
  }
  if (menu == NSApp.mainMenu) {
    NSString *title = DiaZhUntranslatedTitle(item);
    return DiaZhSourceForTitle(title);
  }
  if (menu.supermenu == NSApp.mainMenu) {
    for (NSMenuItem *candidate in NSApp.mainMenu.itemArray) {
      if (candidate.submenu == menu) {
        NSString *title = DiaZhUntranslatedTitle(candidate);
        return DiaZhSourceForTitle(title);
      }
    }
  }
  return nil;
}

static NSDictionary<NSString *, NSSet<NSString *> *> *
DiaZhProtectedMenuKeys(void) {
  static NSDictionary<NSString *, NSSet<NSString *> *> *protectedKeys;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    protectedKeys = @{
      @"Bookmarks": [NSSet setWithArray:@[
        @"Bookmarks",
        @"Bookmark This Page",
        @"Manage Bookmarks",
        @"Recent Bookmarks",
        @"Empty"
      ]],
      @"History": [NSSet setWithArray:@[
        @"History",
        @"Show History…",
        @"Show History...",
        @"Empty"
      ]],
      @"Window": [NSSet setWithArray:@[
        @"Window",
        @"Minimize",
        @"Minimize All",
        @"Bring All to Front",
        @"Downloads",
        @"Task Manager"
      ]]
    };
  });
  return protectedKeys;
}

static NSSet<NSString *> *DiaZhCollisionKeys(void) {
  static NSSet<NSString *> *keys;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    keys = [NSSet setWithArray:@[@"Status", @"Help", @"Window"]];
  });
  return keys;
}

static BOOL DiaZhShouldTranslateItem(NSMenuItem *item, NSString *source) {
  if (!item || !source || ![DiaZhMenuKeys() containsObject:source]) {
    return NO;
  }

  NSString *root = DiaZhRootMenuSource(item);
  NSSet *protectedKeys = DiaZhProtectedMenuKeys()[root];
  if (protectedKeys) {
    return [protectedKeys containsObject:source];
  }

  if ([DiaZhCollisionKeys() containsObject:source]) {
    return root != nil;
  }

  // Deferring until the item belongs to a menu prevents construction-time
  // hooks from changing a bookmark, page, workspace, or window title.
  return item.menu != nil;
}

static NSString *DiaZhDefaultGroupTitle(NSString *title) {
  return [title isEqualToString:@"Imported Tabs"]
    ? DiaZhTranslations()[@"Imported Tabs"] : nil;
}

static BOOL DiaZhIsGroupContextMenu(NSMenuItem *item) {
  // A context menu has no main-menu root. Require group-specific actions as
  // well, so a bookmark/page named like a chat action remains user content.
  if (!item.menu || DiaZhRootMenuSource(item)) {
    return NO;
  }
  for (NSMenuItem *sibling in item.menu.itemArray) {
    NSString *title = DiaZhUntranslatedTitle(sibling);
    NSString *source = DiaZhSourceForTitle(title);
    if ([source isEqualToString:@"Move to Bookmark Bar"] ||
        [source isEqualToString:@"Move to bookmark bar"]) {
      return YES;
    }
  }
  return NO;
}

static NSString *DiaZhDynamicTranslationForItem(
  NSMenuItem *item,
  NSString *title
) {
  NSString *normalized = DiaZhNormalizedSource(title);
  if (!normalized) {
    return nil;
  }

  // First recognize the narrow dynamic action grammar. Scanning every sibling
  // for arbitrary bookmark/view text turns a large submenu into quadratic work.
  for (NSString *source in @[
    @"Chat with \"%@\"", @"Chat With \"%@\"",
    @"Chat with “%@”", @"Chat With “%@”"
  ]) {
    NSString *format = DiaZhTranslations()[source];
    NSString *name;
    if (format && [normalized isEqualToString:
        [NSString stringWithFormat:format, @"Imported Tabs"]]) {
      name = @"Imported Tabs";
    } else {
      NSArray<NSString *> *parts = [source componentsSeparatedByString:@"%@"];
      NSString *prefix = parts.firstObject;
      NSString *suffix = parts.lastObject;
      if ([normalized hasPrefix:prefix] && [normalized hasSuffix:suffix] &&
          normalized.length > prefix.length + suffix.length) {
        name = [normalized substringWithRange:NSMakeRange(
          prefix.length, normalized.length - prefix.length - suffix.length)];
      }
    }
    if (name && DiaZhShouldTranslateItem(item, source) &&
        DiaZhIsGroupContextMenu(item)) {
      return [NSString stringWithFormat:format,
        DiaZhDefaultGroupTitle(name) ?: name];
    }
  }

  if (![normalized hasPrefix:@"Install Update"] &&
      ![normalized hasPrefix:@"Downloading Update"] &&
      ![normalized hasSuffix:@" Tabs"]) {
    return nil;
  }
  NSString *root = DiaZhRootMenuSource(item);

  if ([root isEqualToString:@"Dia"]) {
    for (NSString *source in @[
      @"Install Update…",
      @"Install Update...",
      @"Downloading Update…",
      @"Downloading Update..."
    ]) {
      if ([normalized hasPrefix:source] &&
          DiaZhShouldTranslateItem(item, source)) {
        NSString *translated = DiaZhTranslations()[source];
        NSString *suffix = [normalized substringFromIndex:source.length];
        return [translated stringByAppendingString:suffix];
      }
    }
  }

  if ([root isEqualToString:@"Tabs"]) {
    static NSRegularExpression *tabCountPattern;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      tabCountPattern = [NSRegularExpression
        regularExpressionWithPattern:@"^(.+) — ([0-9]+) Tabs$"
        options:0
        error:nil];
    });
    NSTextCheckingResult *match = [tabCountPattern
      firstMatchInString:normalized
      options:0
      range:NSMakeRange(0, normalized.length)];
    NSString *source = @"%@ — %@ Tabs";
    if (match && DiaZhShouldTranslateItem(item, source)) {
      NSString *profile = [normalized substringWithRange:[match rangeAtIndex:1]];
      NSString *count = [normalized substringWithRange:[match rangeAtIndex:2]];
      return [NSString stringWithFormat:DiaZhTranslations()[source], profile, count];
    }
  }

  return nil;
}

static NSString *DiaZhTranslationForItem(NSMenuItem *item, NSString *title) {
  NSString *source = DiaZhSourceForTitle(title);
  if (DiaZhShouldTranslateItem(item, source)) {
    return DiaZhTranslations()[source];
  }
  return DiaZhDynamicTranslationForItem(item, title);
}

static void DiaZhTranslateStringProperty(
  NSMenuItem *item,
  id object,
  NSString *key
) {
  @try {
    id value = [object valueForKey:key];
    if ([value isKindOfClass:NSString.class]) {
      NSString *translated = DiaZhTranslationForItem(item, value);
      if (translated && ![value isEqualToString:translated]) {
        [object setValue:translated forKey:key];
      }
    } else if ([value isKindOfClass:NSAttributedString.class]) {
      NSAttributedString *attributed = value;
      NSString *translated = DiaZhTranslationForItem(item, attributed.string);
      if (translated) {
        NSMutableAttributedString *localized = attributed.mutableCopy;
        [localized replaceCharactersInRange:NSMakeRange(0, localized.length)
                                 withString:translated];
        [object setValue:localized forKey:key];
      }
    }
  } @catch (__unused NSException *exception) {
  }
}

static void DiaZhTranslateView(NSMenuItem *item, NSView *view) {
  DiaZhTranslateStringProperty(item, view, @"stringValue");
  DiaZhTranslateStringProperty(item, view, @"attributedStringValue");
  DiaZhTranslateStringProperty(item, view, @"title");
  DiaZhTranslateStringProperty(item, view, @"attributedTitle");
  DiaZhTranslateStringProperty(item, view, @"accessibilityLabel");
  DiaZhTranslateStringProperty(item, view, @"accessibilityValue");
  for (NSView *subview in view.subviews) {
    DiaZhTranslateView(item, subview);
  }
}

static BOOL DiaZhClassDeclaresSelector(Class cls, SEL selector) {
  unsigned int count = 0;
  Method *methods = class_copyMethodList(cls, &count);
  BOOL declares = NO;
  for (unsigned int index = 0; index < count; index++) {
    if (method_getName(methods[index]) == selector) {
      declares = YES;
      break;
    }
  }
  free(methods);
  return declares;
}

static IMP DiaZhOriginalImplementation(
  id object,
  NSMutableDictionary<NSString *, NSValue *> *implementations
) {
  for (Class cls = [object class]; cls; cls = class_getSuperclass(cls)) {
    NSValue *value = implementations[NSStringFromClass(cls)];
    if (value) {
      return value.pointerValue;
    }
  }
  return NULL;
}

static void DiaZhSetTitle(NSMenuItem *, SEL, NSString *, IMP);
static NSString *DiaZhTitle(NSMenuItem *, SEL, IMP);
static void DiaZhSetAttributedTitle(NSMenuItem *, SEL, NSAttributedString *, IMP);
static NSAttributedString *DiaZhAttributedTitle(NSMenuItem *, SEL, IMP);

static void DiaZhInstallTitleHooksForClass(Class cls) {
  if (!cls || ![cls isSubclassOfClass:NSMenuItem.class]) {
    return;
  }
  NSString *className = NSStringFromClass(cls);
  SEL selectors[] = {
    @selector(title), @selector(setTitle:),
    @selector(attributedTitle), @selector(setAttributedTitle:)
  };
  NSArray *registries = @[
    DiaZhTitleImplementations, DiaZhSetTitleImplementations,
    DiaZhAttributedTitleImplementations, DiaZhSetAttributedTitleImplementations
  ];
  for (NSUInteger index = 0; index < 4; index++) {
    SEL selector = selectors[index];
    NSMutableDictionary *registry = registries[index];
    if (registry[className] || !DiaZhClassDeclaresSelector(cls, selector)) {
      continue;
    }
    Method method = class_getInstanceMethod(cls, selector);
    IMP original = method_getImplementation(method);
    IMP hook;
    // Bind the original to the class owning this method. Looking it up using
    // item.class inside a super call would select the subclass again forever.
    if (selector == @selector(title)) {
      hook = imp_implementationWithBlock(^NSString *(NSMenuItem *item) {
        return DiaZhTitle(item, selector, original);
      });
    } else if (selector == @selector(setTitle:)) {
      hook = imp_implementationWithBlock(^(NSMenuItem *item, NSString *title) {
        DiaZhSetTitle(item, selector, title, original);
      });
    } else if (selector == @selector(attributedTitle)) {
      hook = imp_implementationWithBlock(^NSAttributedString *(NSMenuItem *item) {
        return DiaZhAttributedTitle(item, selector, original);
      });
    } else {
      hook = imp_implementationWithBlock(^(NSMenuItem *item, NSAttributedString *title) {
        DiaZhSetAttributedTitle(item, selector, title, original);
      });
    }
    registry[className] = [NSValue valueWithPointer:original];
    method_setImplementation(method, hook);
  }
}

static void DiaZhTranslateMenu(NSMenu *menu) {
  for (NSMenuItem *item in menu.itemArray) {
    DiaZhInstallTitleHooksForClass(item.class);
    NSString *translated = DiaZhTranslationForItem(item, item.title);
    if (translated && ![item.title isEqualToString:translated]) {
      item.title = translated;
    }
    // Submenus may contain thousands of bookmark rows. Translate them when
    // they begin tracking, not recursively while opening their parent menu.
    if (item.view) {
      DiaZhTranslateView(item, item.view);
    }
  }
}

static void DiaZhTranslateAllMenus(void);

static char DiaZhTrackingTokenKey;

static void DiaZhTranslateTrackedMenu(NSMenu *menu) {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    [NSNotificationCenter.defaultCenter
      addObserverForName:NSMenuDidEndTrackingNotification
      object:nil queue:NSOperationQueue.mainQueue
      usingBlock:^(NSNotification *notification) {
        if ([notification.object isKindOfClass:NSMenu.class]) {
          objc_setAssociatedObject(notification.object, &DiaZhTrackingTokenKey,
            nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
      }];
  });
  NSObject *token = [[NSObject alloc] init];
  objc_setAssociatedObject(menu, &DiaZhTrackingTokenKey, token,
    OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  // One pass for existing items, one for items attached during menu opening.
  // Closing/reopening the menu invalidates queued work from the old session.
  for (NSNumber *delay in @[@0.0, @0.1]) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
        (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        if (objc_getAssociatedObject(menu, &DiaZhTrackingTokenKey) == token) {
          DiaZhTranslateMenu(menu);
        }
      });
  }
}

static void DiaZhTranslateAllMenus(void) {
  if (NSApp.mainMenu) {
    DiaZhTranslateMenu(NSApp.mainMenu);
  }
}

static NSString *DiaZhTitle(NSMenuItem *item, SEL selector, IMP original) {
  BOOL translate = DiaZhMenuTranslationDepth++ == 0;
  @try {
    NSString *title = ((NSString *(*)(id, SEL))original)(item, selector);
    return translate ? (DiaZhTranslationForItem(item, title) ?: title) : title;
  } @finally {
    --DiaZhMenuTranslationDepth;
  }
}

static void DiaZhSetTitle(
  NSMenuItem *item, SEL selector, NSString *title, IMP original
) {
  BOOL translate = DiaZhMenuTranslationDepth++ == 0;
  @try {
    NSString *localized = translate ? DiaZhTranslationForItem(item, title) : nil;
    ((void (*)(id, SEL, NSString *))original)(item, selector, localized ?: title);
  } @finally {
    --DiaZhMenuTranslationDepth;
  }
}

static NSAttributedString *DiaZhAttributedTitle(
  NSMenuItem *item, SEL selector, IMP original
) {
  BOOL translate = DiaZhMenuTranslationDepth++ == 0;
  @try {
    NSAttributedString *title =
      ((NSAttributedString *(*)(id, SEL))original)(item, selector);
    NSString *translated = translate
      ? DiaZhTranslationForItem(item, title.string) : nil;
    if (!translated || [translated isEqualToString:title.string]) {
      return title;
    }
    NSMutableAttributedString *localized = title.mutableCopy;
    [localized replaceCharactersInRange:NSMakeRange(0, localized.length)
                             withString:translated];
    return localized;
  } @finally {
    --DiaZhMenuTranslationDepth;
  }
}

static void DiaZhSetAttributedTitle(
  NSMenuItem *item, SEL selector, NSAttributedString *title, IMP original
) {
  BOOL translate = DiaZhMenuTranslationDepth++ == 0;
  @try {
    NSString *translated = translate
      ? DiaZhTranslationForItem(item, title.string) : nil;
    if (translated && ![translated isEqualToString:title.string]) {
      NSMutableAttributedString *localized = title.mutableCopy;
      [localized replaceCharactersInRange:NSMakeRange(0, localized.length)
                               withString:translated];
      title = localized;
    }
    ((void (*)(id, SEL, NSAttributedString *))original)(item, selector, title);
  } @finally {
    --DiaZhMenuTranslationDepth;
  }
}

static void DiaZhInstallTitleHook(void) {
  DiaZhSetTitleImplementations = NSMutableDictionary.dictionary;
  DiaZhSetAttributedTitleImplementations = NSMutableDictionary.dictionary;
  DiaZhTitleImplementations = NSMutableDictionary.dictionary;
  DiaZhAttributedTitleImplementations = NSMutableDictionary.dictionary;
  DiaZhInstallTitleHooksForClass(NSMenuItem.class);
}

static IMP DiaZhGroupLabelSetString;
static IMP DiaZhGroupLabelSetAttributedString;
static IMP DiaZhGroupLabelLayout;

static BOOL DiaZhIsDefaultGroupLabel(NSTextField *label) {
  if (label.editable || label.currentEditor) {
    return NO;
  }
  // Only Dia's read-only group-header label, never tab cells, rename fields,
  // bookmark labels or web content. Unknown future view hierarchies fail closed.
  for (NSView *view = label.superview; view; view = view.superview) {
    NSString *name = NSStringFromClass(view.class);
    if ([name isEqualToString:@"TabUI.TabGroupCellView"] ||
        [name isEqualToString:@"TabUI.TabGroupView"] ||
        [name isEqualToString:@"_TtC5TabUI16TabGroupCellView"] ||
        [name isEqualToString:@"_TtC5TabUI12TabGroupView"]) {
      return YES;
    }
    if (![name isEqualToString:@"NSView"] &&
        ![name isEqualToString:@"ARCUI.FlippedView"] &&
        ![name isEqualToString:@"_TtC5ARCUI11FlippedView"] &&
        !([name hasPrefix:@"TabUI.TabGroupView."] &&
          [name hasSuffix:@".HeaderView"]) &&
        !([name hasPrefix:@"_TtCC5TabUI12TabGroupView"] &&
          [name hasSuffix:@"10HeaderView"])) {
      return NO;
    }
  }
  return NO;
}

static void DiaZhGroupLabelSetStringValue(
  NSTextField *label, SEL selector, NSString *value
) {
  NSString *translated = DiaZhIsDefaultGroupLabel(label)
    ? DiaZhDefaultGroupTitle(value) : nil;
  ((void (*)(id, SEL, NSString *))DiaZhGroupLabelSetString)(
    label, selector, translated ?: value);
}

static void DiaZhGroupLabelSetAttributedStringValue(
  NSTextField *label, SEL selector, NSAttributedString *value
) {
  NSString *translated = DiaZhIsDefaultGroupLabel(label)
    ? DiaZhDefaultGroupTitle(value.string) : nil;
  if (translated) {
    NSMutableAttributedString *localized = value.mutableCopy;
    [localized replaceCharactersInRange:NSMakeRange(0, localized.length)
                             withString:translated];
    value = localized;
  }
  ((void (*)(id, SEL, NSAttributedString *))DiaZhGroupLabelSetAttributedString)(
    label, selector, value);
}

static void DiaZhGroupLabelWillLayout(NSTextField *label, SEL selector) {
  // The initial title can be assigned before the label is attached. Applying
  // it before layout also lets AppKit measure the translated text correctly.
  if (DiaZhIsDefaultGroupLabel(label) &&
      DiaZhDefaultGroupTitle(label.stringValue)) {
    label.attributedStringValue = label.attributedStringValue;
  }
  ((void (*)(id, SEL))DiaZhGroupLabelLayout)(label, selector);
}

static void DiaZhInstallGroupTitleHooks(void) {
  if (DiaZhGroupLabelLayout) {
    return;
  }
  Class cls = NSClassFromString(@"_TtC5ARCUI24FeatheredTruncatingLabel");
  if (!cls || ![cls isSubclassOfClass:NSTextField.class]) {
    return;
  }
  SEL selectors[] = {
    @selector(setStringValue:), @selector(setAttributedStringValue:),
    @selector(layout)
  };
  IMP hooks[] = {
    (IMP)DiaZhGroupLabelSetStringValue,
    (IMP)DiaZhGroupLabelSetAttributedStringValue,
    (IMP)DiaZhGroupLabelWillLayout
  };
  IMP *originals[] = {
    &DiaZhGroupLabelSetString, &DiaZhGroupLabelSetAttributedString,
    &DiaZhGroupLabelLayout
  };
  for (NSUInteger index = 0; index < 3; index++) {
    Method method = class_getInstanceMethod(cls, selectors[index]);
    *originals[index] = method_getImplementation(method);
    // Add inherited methods on this class instead of modifying NSTextField.
    class_replaceMethod(cls, selectors[index], hooks[index],
                        method_getTypeEncoding(method));
  }
}

__attribute__((constructor))
static void DiaZhInstallMenuTranslator(void) {
  // dyld has already loaded us. The app-relative path must not be inherited
  // by nested Chromium helpers, where @executable_path resolves elsewhere.
  // Only clear the exact value installed by dia-zh.command.
  const char *loader = getenv("DYLD_INSERT_LIBRARIES");
  if (loader && strcmp(loader,
      "@executable_path/../Frameworks/DiaZhMenu.dylib") == 0) {
    unsetenv("DYLD_INSERT_LIBRARIES");
  }
  DiaZhInstallTitleHook();
  dispatch_async(dispatch_get_main_queue(), ^{
    DiaZhInstallGroupTitleHooks();
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:NSApplicationDidFinishLaunchingNotification
                       object:nil
                        queue:NSOperationQueue.mainQueue
                   usingBlock:^(__unused NSNotification *notification) {
      DiaZhInstallGroupTitleHooks();
      DiaZhTranslateAllMenus();
    }];
    [center addObserverForName:NSMenuDidBeginTrackingNotification
                       object:nil
                        queue:NSOperationQueue.mainQueue
                   usingBlock:^(NSNotification *notification) {
      NSMenu *menu = notification.object;
      if ([menu isKindOfClass:NSMenu.class]) {
        DiaZhTranslateTrackedMenu(menu);
      }
    }];

    DiaZhTranslateAllMenus();
    for (NSTimeInterval delay = 0.25; delay <= 3.0; delay += 0.25) {
      dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
          DiaZhTranslateAllMenus();
        }
      );
    }
  });
}
