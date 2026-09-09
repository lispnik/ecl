/* ECLRuntime.m -- boot ECL inside an iOS app and evaluate forms in it. */

#import "ECLRuntime.h"

#import <ecl/ecl.h>
#import <objc/message.h>
#import <objc/runtime.h>

/* ECL's headers define bare `t' and other short names; keep UIKit out of this
   translation unit so nothing collides. */

/* The Lisp side of EVALUATE:. Kept here rather than in a .lisp file because a
   file would have to be added to the bundle and found at runtime, and this is
   a hello world. */
static const char *kEvalHelper =
  "(defun ecl-hello-eval (string)"
  "  (handler-case"
  "      (let ((values (multiple-value-list (eval (read-from-string string)))))"
  "        (if values"
  "            (format nil \"~{~S~^~%~}\" values)"
  "            \"; no values\"))"
  "    (error (e) (format nil \"; ~A: ~A\" (type-of e) e))))";

#pragma mark - String bridging

/* ECL strings are sequences of code points, so both directions go through
   UTF-32 rather than assuming the contents are ASCII. */

static NSString *StringFromLisp(cl_object s)
{
  if (s == OBJNULL || !ECL_STRINGP(s)) {
    return @"";
  }
  cl_fixnum length = ecl_length(s);
  if (length <= 0) {
    return @"";
  }
  uint32_t *points = malloc(sizeof(uint32_t) * (size_t)length);
  for (cl_fixnum i = 0; i < length; i++) {
    points[i] = (uint32_t)ecl_char(s, (cl_index)i);
  }
  NSString *result = [[NSString alloc] initWithBytes:points
                                              length:(NSUInteger)length * sizeof(uint32_t)
                                            encoding:NSUTF32LittleEndianStringEncoding];
  free(points);
  return result ?: @"";
}

static cl_object StringToLisp(NSString *s)
{
  NSData *utf32 = [s dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
  const uint32_t *points = (const uint32_t *)utf32.bytes;
  cl_index length = (cl_index)(utf32.length / sizeof(uint32_t));
  cl_object result = ecl_alloc_simple_extended_string(length);
  for (cl_index i = 0; i < length; i++) {
    ecl_char_set(result, i, (ecl_character)points[i]);
  }
  return result;
}

#pragma mark - Runtime

@implementation ECLRuntime

+ (void)boot
{
  static BOOL booted = NO;
  if (booted) {
    return;
  }

  /* The bundle is read-only, so point HOME at the one directory the app may
     write to. Anything in Lisp that opens a file relative to ~ lands there. */
  NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                            NSUserDomainMask,
                                                            YES).firstObject;
  setenv("HOME", documents.fileSystemRepresentation, 1);

  /* ECL normally installs handlers for these so it can turn them into Lisp
     conditions. On iOS that fights with the system and with the debugger, so
     the signals are left alone -- a Lisp stack overflow becomes a crash
     instead of a condition, which is the right trade here. */
  ecl_set_option(ECL_OPT_TRAP_SIGSEGV, 0);
  ecl_set_option(ECL_OPT_TRAP_SIGFPE, 0);
  ecl_set_option(ECL_OPT_TRAP_SIGINT, 0);
  ecl_set_option(ECL_OPT_TRAP_SIGILL, 0);
  ecl_set_option(ECL_OPT_TRAP_SIGBUS, 0);
  ecl_set_option(ECL_OPT_TRAP_SIGPIPE, 0);
  ecl_set_option(ECL_OPT_TRAP_INTERRUPT_SIGNAL, 0);
  ecl_set_option(ECL_OPT_SIGNAL_HANDLING_THREAD, 0);

  char *argv[] = { (char *)"ECLHello", NULL };
  cl_boot(1, argv);

  /* There is no C compiler on the phone, so COMPILE has to go through the
     bytecodes compiler. Without this, anything that compiles a function --
     including some of CLOS -- fails. */
  si_safe_eval(3, ecl_read_from_cstring("(ext:install-bytecodes-compiler)"),
               ECL_NIL, ECL_NIL);

  si_safe_eval(3, ecl_read_from_cstring(kEvalHelper), ECL_NIL, ECL_NIL);

  booted = YES;
}

+ (NSString *)loadBundledLispNamed:(NSString *)name
{
  NSString *path = [NSBundle.mainBundle pathForResource:name ofType:@"lisp"];
  if (path == nil) {
    return [NSString stringWithFormat:@"; %@.lisp is missing from the bundle", name];
  }
  /* Routed through ECL-HELLO-EVAL rather than si_safe_eval so that a bad form
     in the file comes back as text instead of vanishing. Bundle paths contain
     no quotes, so interpolating one here is safe. */
  NSString *result = [self evaluate:[NSString stringWithFormat:@"(load \"%@\")", path]];
  return [result hasPrefix:@";"] ? result : @"";
}

+ (void)installObjCBridge
{
  /* The iOS build is static, so ENABLE_DLOPEN is off and
     SI:FIND-FOREIGN-SYMBOL refuses to resolve anything. Handing the addresses
     over directly sidesteps that entirely -- these three are already linked
     into this binary, and SI:CALL-CFUN (libffi) does not need dlsym. */
  cl_env_ptr env = ecl_process_env();
  ecl_setq(env, ecl_make_symbol("*OBJC-GET-CLASS*", "CL-USER"),
           ecl_make_pointer((void *)&objc_getClass));
  ecl_setq(env, ecl_make_symbol("*OBJC-SEL-REGISTER*", "CL-USER"),
           ecl_make_pointer((void *)&sel_registerName));
  ecl_setq(env, ecl_make_symbol("*OBJC-MSG-SEND*", "CL-USER"),
           ecl_make_pointer((void *)&objc_msgSend));
}

+ (void)setCanvas:(UIView *)view
{
  /* A plain foreign pointer -- Lisp passes it straight back to objc_msgSend
     as the receiver. The view is owned by the view hierarchy; Lisp only
     borrows the address, so there is no retain here. */
  cl_object symbol = ecl_make_symbol("*CANVAS*", "CL-USER");
  ecl_setq(ecl_process_env(), symbol, ecl_make_pointer((__bridge void *)view));
}

+ (NSString *)banner
{
  cl_object form = ecl_read_from_cstring
    ("(format nil \"~A ~A~%~A / ~A~%~D-bit fixnums, ~D features\""
     "        (lisp-implementation-type) (lisp-implementation-version)"
     "        (machine-type) (software-type)"
     "        (integer-length most-positive-fixnum) (length *features*))");
  return StringFromLisp(si_safe_eval(3, form, ECL_NIL, ECL_NIL));
}

+ (NSString *)evaluate:(NSString *)source
{
  /* (ecl-hello-eval 'source) -- the string is quoted so the reader never sees
     the user's text, only ECL-HELLO-EVAL does. */
  cl_object quote = ecl_make_symbol("QUOTE", "COMMON-LISP");
  cl_object helper = ecl_make_symbol("ECL-HELLO-EVAL", "CL-USER");
  cl_object form = cl_list(2, helper, cl_list(2, quote, StringToLisp(source)));

  cl_object result = si_safe_eval(3, form, ECL_NIL, ECL_NIL);
  if (result == ECL_NIL) {
    /* Only reachable if ECL-HELLO-EVAL itself blew up. */
    return @"; the evaluator failed";
  }
  return StringFromLisp(result);
}

@end
