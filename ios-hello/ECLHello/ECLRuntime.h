/* ECLRuntime.h -- the whole of the ECL-facing side of the app. */

#import <Foundation/Foundation.h>

@class UIView;

@interface ECLRuntime : NSObject

/* Boots the Lisp image. Must be called once, from the main thread, before
   anything else here. */
+ (void)boot;

/* "ECL 26.5.5 / aarch64 ..." -- proves the image is really running. */
+ (NSString *)banner;

/* Reads, evaluates and prints one form. Never throws: Lisp errors come back
   as their printed representation. */
+ (NSString *)evaluate:(NSString *)source;

/* Loads <name>.lisp from the app bundle. Returns @"" on success, or the
   error text -- loading is where a typo in the Lisp shows up. */
+ (NSString *)loadBundledLispNamed:(NSString *)name;

/* Hands VIEW to Lisp as CL-USER::*CANVAS*, so Lisp can build into it. */
+ (void)setCanvas:(UIView *)view;

/* Initialises the ahead-of-time compiled module linked in as aot.o. */
+ (void)initAOTModule;

/* Exports the bundle's resource directory as CL-USER::*BUNDLE-PATH*. */
+ (void)setBundlePath;

@end
