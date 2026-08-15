#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

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

  __block NSString *source;
  [DiaZhTranslations() enumerateKeysAndObjectsUsingBlock:
    ^(NSString *key, NSString *value, BOOL *stop) {
      if ([DiaZhMenuKeys() containsObject:key] &&
          [value isEqualToString:normalized]) {
        source = key;
        *stop = YES;
      }
    }];
  return source;
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
    IMP implementation =
      DiaZhOriginalImplementation(item, DiaZhTitleImplementations);
    NSString *title = implementation
      ? ((NSString *(*)(id, SEL))implementation)(item, @selector(title))
      : item.submenu.title;
    return DiaZhSourceForTitle(title);
  }
  if (menu.supermenu == NSApp.mainMenu) {
    for (NSMenuItem *candidate in NSApp.mainMenu.itemArray) {
      if (candidate.submenu == menu) {
        IMP implementation = DiaZhOriginalImplementation(
          candidate,
          DiaZhTitleImplementations
        );
        NSString *title = implementation
          ? ((NSString *(*)(id, SEL))implementation)(
              candidate,
              @selector(title)
            )
          : menu.title;
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

static NSString *DiaZhDynamicTranslationForItem(
  NSMenuItem *item,
  NSString *title
) {
  NSString *normalized = DiaZhNormalizedSource(title);
  NSString *root = DiaZhRootMenuSource(item);
  if (!normalized || !root) {
    return nil;
  }

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

static void DiaZhSetTitle(NSMenuItem *, SEL, NSString *);
static NSString *DiaZhTitle(NSMenuItem *, SEL);
static void DiaZhSetAttributedTitle(
  NSMenuItem *,
  SEL,
  NSAttributedString *
);
static NSAttributedString *DiaZhAttributedTitle(NSMenuItem *, SEL);

static void DiaZhInstallTitleHooksForClass(Class cls) {
  if (!cls || ![cls isSubclassOfClass:NSMenuItem.class]) {
    return;
  }

  NSString *className = NSStringFromClass(cls);
  if (!DiaZhTitleImplementations[className] &&
      DiaZhClassDeclaresSelector(cls, @selector(title))) {
    Method method = class_getInstanceMethod(cls, @selector(title));
    IMP implementation = method_getImplementation(method);
    if (implementation != (IMP)DiaZhTitle) {
      DiaZhTitleImplementations[className] =
        [NSValue valueWithPointer:implementation];
      method_setImplementation(method, (IMP)DiaZhTitle);
    }
  }

  if (!DiaZhSetTitleImplementations[className] &&
      DiaZhClassDeclaresSelector(cls, @selector(setTitle:))) {
    Method method = class_getInstanceMethod(cls, @selector(setTitle:));
    IMP implementation = method_getImplementation(method);
    if (implementation != (IMP)DiaZhSetTitle) {
      DiaZhSetTitleImplementations[className] =
        [NSValue valueWithPointer:implementation];
      method_setImplementation(method, (IMP)DiaZhSetTitle);
    }
  }

  if (!DiaZhAttributedTitleImplementations[className] &&
      DiaZhClassDeclaresSelector(cls, @selector(attributedTitle))) {
    Method method = class_getInstanceMethod(cls, @selector(attributedTitle));
    IMP implementation = method_getImplementation(method);
    if (implementation != (IMP)DiaZhAttributedTitle) {
      DiaZhAttributedTitleImplementations[className] =
        [NSValue valueWithPointer:implementation];
      method_setImplementation(method, (IMP)DiaZhAttributedTitle);
    }
  }

  if (!DiaZhSetAttributedTitleImplementations[className] &&
      DiaZhClassDeclaresSelector(cls, @selector(setAttributedTitle:))) {
    Method method =
      class_getInstanceMethod(cls, @selector(setAttributedTitle:));
    IMP implementation = method_getImplementation(method);
    if (implementation != (IMP)DiaZhSetAttributedTitle) {
      DiaZhSetAttributedTitleImplementations[className] =
        [NSValue valueWithPointer:implementation];
      method_setImplementation(method, (IMP)DiaZhSetAttributedTitle);
    }
  }
}

static void DiaZhTranslateMenu(NSMenu *menu) {
  for (NSMenuItem *item in menu.itemArray) {
    DiaZhInstallTitleHooksForClass(item.class);
    NSString *translated = DiaZhTranslationForItem(item, item.title);
    if (translated && ![item.title isEqualToString:translated]) {
      item.title = translated;
    }
    if (item.submenu) {
      DiaZhTranslateMenu(item.submenu);
    }
    if (item.view) {
      DiaZhTranslateView(item, item.view);
    }
  }
}

static void DiaZhTranslateAllMenus(void);

static void DiaZhTranslateMenuWindows(void) {
  for (NSWindow *window in NSApp.windows) {
    NSString *className = NSStringFromClass(window.class).lowercaseString;
    if ([className containsString:@"menu"] ||
        window.level >= NSPopUpMenuWindowLevel) {
      for (NSMenuItem *item in NSApp.mainMenu.itemArray) {
        if (item.view && item.view.window == window) {
          DiaZhTranslateView(item, window.contentView);
          break;
        }
      }
    }
  }
}

static void DiaZhTranslateTrackedMenu(NSMenu *menu) {
  const NSTimeInterval delays[] = {
    0.0, 0.01, 0.03, 0.05, 0.10, 0.15, 0.25, 0.40, 0.70
  };
  const NSUInteger count = sizeof(delays) / sizeof(delays[0]);
  for (NSUInteger index = 0; index < count; index++) {
    dispatch_after(
      dispatch_time(
        DISPATCH_TIME_NOW,
        (int64_t)(delays[index] * NSEC_PER_SEC)
      ),
      dispatch_get_main_queue(),
      ^{
        DiaZhTranslateMenu(menu);
        DiaZhTranslateAllMenus();
        DiaZhTranslateMenuWindows();
      }
    );
  }
}

static void DiaZhTranslateAllMenus(void) {
  if (NSApp.mainMenu) {
    DiaZhTranslateMenu(NSApp.mainMenu);
  }
}

static NSString *DiaZhTitle(NSMenuItem *item, SEL selector) {
  IMP implementation =
    DiaZhOriginalImplementation(item, DiaZhTitleImplementations);
  if (!implementation) {
    return @"";
  }
  NSString *title =
    ((NSString *(*)(id, SEL))implementation)(item, selector);
  return DiaZhTranslationForItem(item, title) ?: title;
}

static void DiaZhSetTitle(NSMenuItem *item, SEL selector, NSString *title) {
  NSString *translated = DiaZhTranslationForItem(item, title) ?: title;
  IMP implementation =
    DiaZhOriginalImplementation(item, DiaZhSetTitleImplementations);
  if (implementation) {
    ((void (*)(id, SEL, NSString *))implementation)(
      item,
      selector,
      translated
    );
  }
}

static NSAttributedString *DiaZhAttributedTitle(
  NSMenuItem *item,
  SEL selector
) {
  IMP implementation =
    DiaZhOriginalImplementation(item, DiaZhAttributedTitleImplementations);
  if (!implementation) {
    return nil;
  }

  NSAttributedString *title =
    ((NSAttributedString *(*)(id, SEL))implementation)(item, selector);
  NSString *translated = DiaZhTranslationForItem(item, title.string);
  if (!translated) {
    return title;
  }
  NSMutableAttributedString *localized = title.mutableCopy;
  [localized replaceCharactersInRange:NSMakeRange(0, localized.length)
                           withString:translated];
  return localized;
}

static void DiaZhSetAttributedTitle(
  NSMenuItem *item,
  SEL selector,
  NSAttributedString *title
) {
  IMP implementation =
    DiaZhOriginalImplementation(item, DiaZhSetAttributedTitleImplementations);
  if (!implementation) {
    return;
  }

  NSString *translated = DiaZhTranslationForItem(item, title.string);
  if (!translated) {
    ((void (*)(id, SEL, NSAttributedString *))implementation)(
      item,
      selector,
      title
    );
    return;
  }
  NSMutableAttributedString *localized = title.mutableCopy;
  [localized replaceCharactersInRange:NSMakeRange(0, localized.length)
                           withString:translated];
  ((void (*)(id, SEL, NSAttributedString *))implementation)(
    item,
    selector,
    localized
  );
}

static void DiaZhInstallTitleHook(void) {
  DiaZhSetTitleImplementations = NSMutableDictionary.dictionary;
  DiaZhSetAttributedTitleImplementations = NSMutableDictionary.dictionary;
  DiaZhTitleImplementations = NSMutableDictionary.dictionary;
  DiaZhAttributedTitleImplementations = NSMutableDictionary.dictionary;
  DiaZhInstallTitleHooksForClass(NSMenuItem.class);
}

__attribute__((constructor))
static void DiaZhInstallMenuTranslator(void) {
  DiaZhInstallTitleHook();
  dispatch_async(dispatch_get_main_queue(), ^{
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:NSApplicationDidFinishLaunchingNotification
                       object:nil
                        queue:NSOperationQueue.mainQueue
                   usingBlock:^(__unused NSNotification *notification) {
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
