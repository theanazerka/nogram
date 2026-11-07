// Runs the upstream +load methods (renamed to +tg_deferredLoad by tools/defer-loads.py).
//
// This file is linked LAST, so its constructor runs after all other static
// initializers and before main() — the same phase in which +load used to run.
// Each call is traced and wrapped in @try: an exception is recorded and skipped,
// and a class whose +load crashed the process last time is not called again (the
// launch tracer then gets far enough to show its report).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "TGCrashCatcher.h"

static bool TGClassOwnsMethod(Class metaClass, SEL selector)
{
    unsigned int count = 0;
    Method *methods = class_copyMethodList(metaClass, &count);
    bool found = false;
    for (unsigned int i = 0; i < count && !found; i++)
        found = method_getName(methods[i]) == selector;
    free(methods);
    return found;
}

__attribute__((constructor)) static void TGRunDeferredLoads(void)
{
    @autoreleasepool
    {
        SEL selector = @selector(tg_deferredLoad);
        int classCount = objc_getClassList(NULL, 0);
        Class *classes = (Class *)malloc(sizeof(Class) * (size_t)classCount);
        classCount = objc_getClassList(classes, classCount);

        NSMutableArray *targets = [[NSMutableArray alloc] init];
        for (int i = 0; i < classCount; i++)
        {
            Class metaClass = object_getClass(classes[i]);
            if (metaClass != Nil && TGClassOwnsMethod(metaClass, selector))
                [targets addObject:classes[i]];
        }
        free(classes);

        // Deterministic order (the original +load order was link order).
        [targets sortUsingComparator:^NSComparisonResult(Class a, Class b)
        {
            return [NSStringFromClass(a) compare:NSStringFromClass(b)];
        }];

        TGTraceMarkf(@"deferred +load: %d classes", (int)targets.count);
        for (Class cls in targets)
        {
            NSString *name = NSStringFromClass(cls);
            if (TGTraceShouldSkipDeferredLoad(name))
            {
                TGTraceMarkf(@"+load skipped %@", name);
                continue;
            }
            TGTraceMarkf(@"+load begin %@", name);
            @try
            {
                ((void (*)(id, SEL))objc_msgSend)(cls, selector);
            }
            @catch (NSException *exception)
            {
                TGTraceMarkf(@"+load EXCEPTION in %@: %@ — %@", name, exception.name, exception.reason);
            }
            TGTraceMarkf(@"+load end %@", name);
        }
        TGTraceMark("deferred +load: done");
    }
}
