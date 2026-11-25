#import <Cocoa/Cocoa.h>
#include <signal.h>
#include <unistd.h>
#include "../native/DiaZhMenu.m"

static unsigned int callDepth;
static void EnterOriginal(void) {
  if (++callDepth > 32) {
    fprintf(stderr, "FAIL: menu subclass recursively re-entered its original method\n");
    exit(42);
  }
}

@interface ParentMenuItem : NSMenuItem
@end
@implementation ParentMenuItem
- (NSString *)title {
  EnterOriginal(); NSString *value = [super title]; --callDepth; return value;
}
- (void)setTitle:(NSString *)value {
  EnterOriginal(); [super setTitle:value]; --callDepth;
}
- (NSAttributedString *)attributedTitle {
  EnterOriginal(); NSAttributedString *value = [super attributedTitle];
  --callDepth; return value;
}
- (void)setAttributedTitle:(NSAttributedString *)value {
  EnterOriginal(); [super setAttributedTitle:value]; --callDepth;
}
@end

@interface ChildMenuItem : ParentMenuItem
@end
@implementation ChildMenuItem
- (NSString *)title {
  EnterOriginal(); NSString *value = [super title]; --callDepth; return value;
}
- (void)setTitle:(NSString *)value {
  EnterOriginal(); [super setTitle:value]; --callDepth;
}
- (NSAttributedString *)attributedTitle {
  EnterOriginal(); NSAttributedString *value = [super attributedTitle];
  --callDepth; return value;
}
- (void)setAttributedTitle:(NSAttributedString *)value {
  EnterOriginal(); [super setAttributedTitle:value]; --callDepth;
}
@end

// Original accessors may consult a sibling's public title, re-entering the
// translator while it is classifying a context menu.
@interface SiblingReadingMenuItem : ChildMenuItem
@property(nonatomic, weak) NSMenuItem *peer;
@end
@implementation SiblingReadingMenuItem
- (NSString *)title {
  EnterOriginal();
  if (self.peer) (void)self.peer.title;
  NSString *value = [super title];
  --callDepth;
  return value;
}
@end

static NSMenuItem *AddItem(NSMenu *menu, Class cls, NSString *title) {
  NSMenuItem *item = [[cls alloc] initWithTitle:title action:nil keyEquivalent:@""];
  [menu addItem:item];
  return item;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc != 2) return 2;
    // A regression must fail CI promptly, rather than hang the test runner.
    alarm(10);
    setenv("DIA_ZH_RESOURCE_ROOT", argv[1], 1);
    [NSApplication sharedApplication];
    NSMenu *main = [[NSMenu alloc] initWithTitle:@"Main"];
    NSApp.mainMenu = main;
    NSMenuItem *top = AddItem(main, ChildMenuItem.class, @"Bookmarks");
    NSMenu *bookmarks = [[NSMenu alloc] initWithTitle:@"Bookmarks"];
    top.submenu = bookmarks;
    NSMenuItem *userTitle = AddItem(bookmarks, ChildMenuItem.class, @"Copy All Links");
    NSMenu *group = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *parent = AddItem(group, ParentMenuItem.class, @"Add Icon");
    NSMenuItem *child = AddItem(group, ChildMenuItem.class, @"Copy All Links");
    SiblingReadingMenuItem *move = (id)AddItem(group,
      SiblingReadingMenuItem.class, @"Move to Bookmark Bar");
    NSMenuItem *chat = AddItem(group, ChildMenuItem.class, @"Chat with \"Imported Tabs\"");
    move.peer = chat;
    DiaZhTranslateMenu(main);
    DiaZhTranslateMenu(group);
    for (NSUInteger i = 0; i < 50; i++) {
      // Repeated discovery must not wrap an already wrapped implementation.
      DiaZhTranslateMenu(group);
      parent.title = @"Add Icon";
      child.title = @"Copy All Links";
      NSCAssert([parent.title isEqualToString:@"添加图标"], @"parent getter/setter");
      NSCAssert([child.title isEqualToString:@"复制所有链接"], @"child getter/setter");
      NSCAssert([chat.title isEqualToString:@"与“已导入的标签页”聊天"],
        @"dynamic group action with sibling-reading original getter");
      NSCAssert([userTitle.title isEqualToString:@"Copy All Links"],
        @"protected menu root resolved through subclass original getter");
      child.attributedTitle = [[NSAttributedString alloc] initWithString:@"Copy All Links"
        attributes:@{NSForegroundColorAttributeName:NSColor.redColor}];
      NSCAssert([child.attributedTitle.string isEqualToString:@"复制所有链接"],
        @"attributed getter/setter");
      NSCAssert([[child.attributedTitle attribute:NSForegroundColorAttributeName
        atIndex:0 effectiveRange:NULL] isEqual:NSColor.redColor], @"preserve attributes");
    }
    // Run the same delayed traversal used when a real right-click menu opens.
    __block BOOL responsive = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ responsive = YES; });
    DiaZhTranslateTrackedMenu(group);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
    while (deadline.timeIntervalSinceNow > 0) {
      [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
    }
    NSCAssert(responsive && callDepth == 0, @"menu tracking must leave main queue responsive");
    alarm(0);
    NSLog(@"Menu subclass and reentrancy fixture passed.");
  }
  return 0;
}
