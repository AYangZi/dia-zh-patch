#import <Cocoa/Cocoa.h>

#include "../native/DiaZhMenu.m"

static void AssertPolicy(
  NSMenuItem *item,
  NSString *source,
  BOOL expected,
  NSString *message
) {
  BOOL actual = DiaZhShouldTranslateItem(item, source);
  if (actual != expected) {
    NSLog(@"FAIL: %@ (expected %d, got %d)", message, expected, actual);
    exit(1);
  }
}

static NSMenu *AddTopLevelMenu(NSMenu *mainMenu, NSString *title) {
  NSMenuItem *top = [[NSMenuItem alloc] initWithTitle:title
                                               action:nil
                                        keyEquivalent:@""];
  NSMenu *submenu = [[NSMenu alloc] initWithTitle:title];
  top.submenu = submenu;
  [mainMenu addItem:top];
  return submenu;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc != 2) {
      return 2;
    }
    setenv("DIA_ZH_RESOURCE_ROOT", argv[1], 1);
    [NSApplication sharedApplication];

    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"Main"];
    NSApp.mainMenu = mainMenu;
    NSMenu *app = AddTopLevelMenu(mainMenu, @"Dia");
    NSMenu *tabs = AddTopLevelMenu(mainMenu, @"Tabs");
    NSMenu *bookmarks = AddTopLevelMenu(mainMenu, @"Bookmarks");
    NSMenu *history = AddTopLevelMenu(mainMenu, @"History");
    NSMenu *window = AddTopLevelMenu(mainMenu, @"Window");
    NSMenu *help = AddTopLevelMenu(mainMenu, @"Help");
    NSMenu *file = AddTopLevelMenu(mainMenu, @"File");

    NSMenuItem *bookmarkAction =
      [[NSMenuItem alloc] initWithTitle:@"Bookmark This Page"
                                action:nil keyEquivalent:@""];
    [bookmarks addItem:bookmarkAction];
    AssertPolicy(bookmarkAction, @"Bookmark This Page", YES,
      @"fixed bookmark action should translate");

    for (NSString *collision in @[@"Status", @"Help", @"Window", @"Copy"]) {
      NSMenuItem *userBookmark =
        [[NSMenuItem alloc] initWithTitle:collision action:nil keyEquivalent:@""];
      [bookmarks addItem:userBookmark];
      AssertPolicy(userBookmark, collision, NO,
        @"bookmark title must remain user-controlled");
    }

    NSMenuItem *historyTitle =
      [[NSMenuItem alloc] initWithTitle:@"Help" action:nil keyEquivalent:@""];
    [history addItem:historyTitle];
    AssertPolicy(historyTitle, @"Help", NO,
      @"history title must remain user-controlled");

    NSMenuItem *windowTitle =
      [[NSMenuItem alloc] initWithTitle:@"Status" action:nil keyEquivalent:@""];
    [window addItem:windowTitle];
    AssertPolicy(windowTitle, @"Status", NO,
      @"window title must remain user-controlled");

    NSMenuItem *helpStatus =
      [[NSMenuItem alloc] initWithTitle:@"Status" action:nil keyEquivalent:@""];
    [help addItem:helpStatus];
    AssertPolicy(helpStatus, @"Status", YES,
      @"fixed Help menu status should translate");

    NSMenuItem *copy =
      [[NSMenuItem alloc] initWithTitle:@"Copy" action:nil keyEquivalent:@""];
    [file addItem:copy];
    AssertPolicy(copy, @"Copy", YES,
      @"fixed File menu item should translate");

    NSMenuItem *installUpdate =
      [[NSMenuItem alloc] initWithTitle:@"Install Update…，1.44.1 (85212)"
                                action:nil keyEquivalent:@""];
    [app addItem:installUpdate];
    NSCAssert(
      [installUpdate.title isEqualToString:@"安装更新…，1.44.1 (85212)"],
      @"dynamic update version should translate without changing the version"
    );

    NSMenuItem *tabCount =
      [[NSMenuItem alloc] initWithTitle:@"Work — 30 Tabs"
                                action:nil keyEquivalent:@""];
    [tabs addItem:tabCount];
    NSCAssert(
      [tabCount.title isEqualToString:@"Work — 30 个标签页"],
      @"dynamic tab count should preserve the profile name"
    );

    NSMenuItem *bookmarkTabCount =
      [[NSMenuItem alloc] initWithTitle:@"Work — 30 Tabs"
                                action:nil keyEquivalent:@""];
    [bookmarks addItem:bookmarkTabCount];
    NSCAssert(
      [bookmarkTabCount.title isEqualToString:@"Work — 30 Tabs"],
      @"bookmark text resembling a tab count must remain user-controlled"
    );

    NSMenuItem *detached =
      [[NSMenuItem alloc] initWithTitle:@"Help" action:nil keyEquivalent:@""];
    AssertPolicy(detached, @"Help", NO,
      @"detached construction-time title should not translate");

    NSLog(@"Menu collision policy passed.");
  }
  return 0;
}
