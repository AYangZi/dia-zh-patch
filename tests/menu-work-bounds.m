#import <Cocoa/Cocoa.h>
#include <unistd.h>
#include "../native/DiaZhMenu.m"

static NSUInteger titleReads;
static NSUInteger titleReadLimit = NSUIntegerMax;
@interface CountingTitleItem : NSMenuItem
@end
@implementation CountingTitleItem
- (NSString *)title {
  if (++titleReads > titleReadLimit) {
    fprintf(stderr, "FAIL: menu translation repeatedly scans unrelated sibling titles\n");
    exit(43);
  }
  return [super title];
}
@end

static NSMenuItem *Item(NSMenu *menu, NSString *title) {
  NSMenuItem *item = [[CountingTitleItem alloc]
    initWithTitle:title action:nil keyEquivalent:@""];
  [menu addItem:item];
  return item;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc != 2) return 2;
    alarm(10);
    setenv("DIA_ZH_RESOURCE_ROOT", argv[1], 1);
    [NSApplication sharedApplication];
    // Build a large bookmark-folder context submenu without spending the test
    // budget in incidental AppKit accessor calls during fixture construction.
    ++DiaZhMenuTranslationDepth;
    NSMenu *root = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *folder = Item(root, @"Add Bookmark to Folder");
    NSMenu *large = [[NSMenu alloc] initWithTitle:@"Folders"];
    folder.submenu = large;
    const NSUInteger count = 300;
    for (NSUInteger i = 0; i < count; i++) {
      NSString *title = [NSString stringWithFormat:@"User folder %lu", (unsigned long)i];
      NSMenuItem *item = Item(large, title);
      NSView *view = [[NSView alloc] init];
      [view addSubview:[NSTextField labelWithString:title]];
      item.view = view;
    }
    --DiaZhMenuTranslationDepth;
    titleReads = 0;
    titleReadLimit = 16 * count;
    DiaZhTranslateMenu(large);
    NSCAssert(titleReads <= titleReadLimit,
      @"display work must grow linearly, not scan every sibling for every property");
    titleReads = 0;
    titleReadLimit = 20;
    DiaZhTranslateMenu(root);
    NSCAssert(titleReads <= titleReadLimit,
      @"opening a parent menu must not eagerly traverse its unopened submenu");
    // After tracking ends, queued work must not stall the next tab click.
    titleReads = 0;
    titleReadLimit = 0;
    DiaZhTranslateTrackedMenu(root);
    [NSNotificationCenter.defaultCenter
      postNotificationName:NSMenuDidEndTrackingNotification object:root];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.8];
    while (deadline.timeIntervalSinceNow > 0) {
      [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
    }
    NSCAssert(titleReads == 0, @"closed menus must not keep translating");
    alarm(0);
    NSLog(@"Menu work bounds fixture passed.");
  }
  return 0;
}
