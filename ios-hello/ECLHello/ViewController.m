/* ViewController.m -- a transcript and one input line, wired to ECLRuntime. */

#import "ViewController.h"
#import "ECLRuntime.h"

/* Buttons, as {label, form} pairs. Each one is evaluated by the same code
   path as typed input, so they double as a demo and as a way to drive the app
   without a keyboard. */
static NSArray<NSArray<NSString *> *> *DemoButtons(void)
{
  static NSArray *demos;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    demos = @[
      /* GET with a default is a self-initialising place, so the counter needs
         no DEFVAR -- and it proves the image keeps state between taps. */
      @[ @"Tap", @"(incf (get 'demo 'taps 0))" ],

      @[ @"Time", @"(multiple-value-bind (s m h) (get-decoded-time)"
                  @"  (format nil \"~2,'0D:~2,'0D:~2,'0D\" h m s))" ],

      @[ @"Fib 25", @"(labels ((fib (n) (if (< n 2) n (+ (fib (- n 1))"
                    @"                                   (fib (- n 2))))))"
                    @"  (fib 25))" ],

      /* The one most likely to break on iOS: CLOS leans on COMPILE, which
         only works because boot installed the bytecodes compiler. */
      @[ @"CLOS", @"(progn"
                  @"  (defclass pt () ((x :initform 3) (y :initform 4)))"
                  @"  (defmethod norm ((p pt))"
                  @"    (sqrt (+ (* (slot-value p 'x) (slot-value p 'x))"
                  @"             (* (slot-value p 'y) (slot-value p 'y)))))"
                  @"  (norm (make-instance 'pt)))" ],

      /* Builds a real UIKit view hierarchy from Lisp -- see lisp/gui.lisp. */
      @[ @"Lisp GUI", @"(build-demo-gui)" ],

      @[ @"Clear", @"" ],
    ];
  });
  return demos;
}

@interface ViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextView *transcript;
@property (nonatomic, strong) UITextField *input;
@property (nonatomic, strong) UIScrollView *buttonBar;
@property (nonatomic, strong) UIView *canvas;
@property (nonatomic, strong) NSLayoutConstraint *inputBottom;
@end

@implementation ViewController

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.systemBackgroundColor;

  self.transcript = [[UITextView alloc] init];
  self.transcript.translatesAutoresizingMaskIntoConstraints = NO;
  self.transcript.editable = NO;
  self.transcript.font = [UIFont monospacedSystemFontOfSize:13
                                                     weight:UIFontWeightRegular];
  self.transcript.backgroundColor = UIColor.secondarySystemBackgroundColor;
  self.transcript.alwaysBounceVertical = YES;
  [self.view addSubview:self.transcript];

  self.input = [[UITextField alloc] init];
  self.input.translatesAutoresizingMaskIntoConstraints = NO;
  self.input.delegate = self;
  self.input.font = [UIFont monospacedSystemFontOfSize:15
                                                weight:UIFontWeightRegular];
  self.input.placeholder = @"(+ 1 2)";
  self.input.borderStyle = UITextBorderStyleRoundedRect;
  self.input.returnKeyType = UIReturnKeyDone;
  self.input.autocorrectionType = UITextAutocorrectionTypeNo;
  self.input.autocapitalizationType = UITextAutocapitalizationTypeNone;
  self.input.smartQuotesType = UITextSmartQuotesTypeNo;
  self.input.smartDashesType = UITextSmartDashesTypeNo;
  [self.view addSubview:self.input];

  /* The patch of screen Lisp is allowed to build into. */
  self.canvas = [[UIView alloc] init];
  self.canvas.translatesAutoresizingMaskIntoConstraints = NO;
  self.canvas.backgroundColor = UIColor.tertiarySystemBackgroundColor;
  self.canvas.layer.cornerRadius = 8;
  self.canvas.layer.borderWidth = 1;
  self.canvas.layer.borderColor = UIColor.separatorColor.CGColor;
  [self.view addSubview:self.canvas];

  /* A horizontally scrolling row, so the labels never have to be squeezed to
     fit the narrowest phone. */
  UIStackView *row = [[UIStackView alloc] init];
  row.translatesAutoresizingMaskIntoConstraints = NO;
  row.axis = UILayoutConstraintAxisHorizontal;
  row.spacing = 8;

  [DemoButtons() enumerateObjectsUsingBlock:^(NSArray<NSString *> *demo,
                                              NSUInteger index, BOOL *stop) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config = [UIButtonConfiguration tintedButtonConfiguration];
    config.title = demo.firstObject;
    config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    config.buttonSize = UIButtonConfigurationSizeSmall;
    button.configuration = config;
    button.tag = (NSInteger)index;
    [button addTarget:self
               action:@selector(demoButtonTapped:)
     forControlEvents:UIControlEventTouchUpInside];
    [row addArrangedSubview:button];
  }];

  self.buttonBar = [[UIScrollView alloc] init];
  self.buttonBar.translatesAutoresizingMaskIntoConstraints = NO;
  self.buttonBar.showsHorizontalScrollIndicator = NO;
  [self.buttonBar addSubview:row];
  [self.view addSubview:self.buttonBar];

  UILayoutGuide *content = self.buttonBar.contentLayoutGuide;
  UILayoutGuide *frame = self.buttonBar.frameLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [row.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
    [row.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
    [row.topAnchor constraintEqualToAnchor:content.topAnchor],
    [row.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    [row.heightAnchor constraintEqualToAnchor:frame.heightAnchor],
  ]];

  UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
  self.inputBottom = [self.input.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor
                                                            constant:-8];
  [NSLayoutConstraint activateConstraints:@[
    [self.transcript.topAnchor constraintEqualToAnchor:safe.topAnchor],
    [self.transcript.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],
    [self.transcript.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],
    [self.transcript.bottomAnchor constraintEqualToAnchor:self.canvas.topAnchor constant:-8],
    [self.canvas.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],
    [self.canvas.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],
    [self.canvas.heightAnchor constraintEqualToConstant:88],
    [self.canvas.bottomAnchor constraintEqualToAnchor:self.buttonBar.topAnchor constant:-8],
    [self.buttonBar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],
    [self.buttonBar.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],
    [self.buttonBar.heightAnchor constraintEqualToConstant:34],
    [self.buttonBar.bottomAnchor constraintEqualToAnchor:self.input.topAnchor constant:-8],
    [self.input.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],
    [self.input.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],
    self.inputBottom,
  ]];

  [NSNotificationCenter.defaultCenter addObserver:self
                                         selector:@selector(keyboardWillChange:)
                                             name:UIKeyboardWillChangeFrameNotification
                                           object:nil];

  /* Booting takes a moment; do it before the first frame so the banner is
     already on screen when the window appears. */
  [ECLRuntime boot];
  [self append:[ECLRuntime banner]];

  /* Both installs have to come after the load: gui.lisp DEFPARAMETERs these
     variables, which would clobber anything set beforehand. */
  NSString *guiError = [ECLRuntime loadBundledLispNamed:@"gui"];
  [ECLRuntime installObjCBridge];
  [ECLRuntime setCanvas:self.canvas];
  if (guiError.length > 0) {
    [self append:[NSString stringWithFormat:@"\ngui.lisp: %@", guiError]];
  }

  /* Run a few forms through exactly the path the input field uses, so the
     first screen shows the runtime working rather than just claiming to. */
  for (NSString *demo in @[ @"(+ 1 2)",
                            @"(mapcar #'1+ '(1 2 3))",
                            @"(format nil \"~R\" 1234)",
                            @"(code-char 233)",
                            @"(loop for i below 5 collect (expt 2 i))",
                            @"(car 5)" ]) {
    [self evaluateAndShow:demo];
  }

  [self append:@"\nTap a button, or type a form below and press Done."];
}

- (void)evaluateAndShow:(NSString *)source
{
  [self append:[NSString stringWithFormat:@"\n> %@", source]];
  [self append:[ECLRuntime evaluate:source]];
}

- (void)demoButtonTapped:(UIButton *)sender
{
  NSString *source = DemoButtons()[(NSUInteger)sender.tag].lastObject;
  if (source.length == 0) {          /* the Clear button carries no form */
    self.transcript.text = @"";
    return;
  }
  [self evaluateAndShow:source];
}

- (void)append:(NSString *)text
{
  NSString *combined = self.transcript.text.length > 0
    ? [NSString stringWithFormat:@"%@\n%@", self.transcript.text, text]
    : text;
  self.transcript.text = combined;

  if (combined.length > 0) {
    [self.transcript scrollRangeToVisible:NSMakeRange(combined.length - 1, 1)];
  }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
  NSString *source = textField.text;
  if (source.length > 0) {
    [self evaluateAndShow:source];
    textField.text = @"";
  }
  [textField resignFirstResponder];
  return NO;
}

- (void)keyboardWillChange:(NSNotification *)note
{
  CGRect frame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
  CGFloat overlap = CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(frame);
  self.inputBottom.constant = -8 - MAX(0, overlap - self.view.safeAreaInsets.bottom);
  [self.view layoutIfNeeded];
}

@end
