#import <Foundation/Foundation.h>
#include <spawn.h>
#include <sys/wait.h>
#include <crt_externs.h>

int main(int argc, char *argv[]) {
  @autoreleasepool {
    if (argc != 2) return 2;
    pid_t child;
    char *arguments[] = {argv[1], NULL};
    int error = posix_spawn(&child, argv[1], NULL, NULL, arguments,
                           *_NSGetEnviron());
    if (error != 0) return 3;
    int status = 0;
    if (waitpid(child, &status, 0) != child) return 4;
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
      NSLog(@"菜单加载 Fixture 失败：辅助进程继承了主程序的相对 DYLD 路径");
      return 1;
    }
  }
  return 0;
}
