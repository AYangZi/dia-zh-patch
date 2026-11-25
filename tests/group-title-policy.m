#import <Cocoa/Cocoa.h>
#include "../native/DiaZhMenu.m"

static Class ViewClass(const char *name, Class parent) {
  Class cls = objc_allocateClassPair(parent, name, 0);
  NSCAssert(cls != Nil, @"fixture class must be unique");
  objc_registerClassPair(cls);
  return cls;
}

static NSTextField *Label(Class cls, NSView *parent, NSString *title) {
  NSTextField *label = [[cls alloc] initWithFrame:NSMakeRect(0, 0, 240, 30)];
  label.editable = NO;
  label.stringValue = title; // Assignment before joining the group hierarchy.
  [parent addSubview:label];
  return label;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc != 2) return 2;
    setenv("DIA_ZH_RESOURCE_ROOT", argv[1], 1);
    [NSApplication sharedApplication];
    Class labelClass = ViewClass("_TtC5ARCUI24FeatheredTruncatingLabel",
      NSTextField.class);
    Class cellClass = ViewClass("_TtC5TabUI16TabGroupCellView", NSControl.class);
    Class groupClass = ViewClass("_TtC5TabUI12TabGroupView", NSControl.class);
    Class tabClass = ViewClass("_TtC5TabUI11TabCellView", NSControl.class);
    Class headerClass = ViewClass(
      "_TtCC5TabUI12TabGroupViewP33_fixture10HeaderView", NSView.class);
    DiaZhInstallGroupTitleHooks();
    DiaZhInstallGroupTitleHooks(); // Idempotent, no hook calling itself.
    NSString *source = @"Imported Tabs";
    NSString *translation = @"已导入的标签页";

    for (Class cls in @[cellClass, groupClass]) {
      NSView *group = [[cls alloc] init];
      NSView *header = [[headerClass alloc] init];
      [group addSubview:header];
      NSTextField *label = Label(labelClass, header, source);
      [label layout];
      NSCAssert([label.stringValue isEqualToString:translation],
        @"existing title should translate on first attached layout");
      label.stringValue = source;
      NSCAssert([label.stringValue isEqualToString:translation],
        @"reused group title should translate on update");
      label.attributedStringValue = [[NSAttributedString alloc]
        initWithString:source attributes:@{NSForegroundColorAttributeName:
          NSColor.redColor}];
      NSCAssert([label.stringValue isEqualToString:translation] &&
        [[label.attributedStringValue attribute:NSForegroundColorAttributeName
          atIndex:0 effectiveRange:NULL] isEqual:NSColor.redColor],
        @"attributed title must preserve its styling");
      for (NSString *custom in @[@"Imported Tabs 2", @"Work", @"工作"] ) {
        label.stringValue = custom;
        [label layout];
        NSCAssert([label.stringValue isEqualToString:custom],
          @"custom group names must remain unchanged");
      }
      label.editable = YES;
      label.stringValue = source;
      [label layout];
      NSCAssert([label.stringValue isEqualToString:source],
        @"editable fields must remain unchanged");
      NSTextField *other = Label(NSTextField.class, header, source);
      [other layout];
      NSCAssert([other.stringValue isEqualToString:source],
        @"ordinary text fields must not be hooked");
      NSView *tab = [[tabClass alloc] init];
      [group addSubview:tab];
      NSTextField *page = Label(labelClass, tab, source);
      [page layout];
      NSCAssert([page.stringValue isEqualToString:source],
        @"a page inside a group is not the group title");
    }
    NSTextField *outside = Label(labelClass, [[NSView alloc] init], source);
    [outside layout];
    NSCAssert([outside.stringValue isEqualToString:source],
      @"same label class outside group headers must remain unchanged");
    NSLog(@"Group title display policy passed.");
  }
  return 0;
}
