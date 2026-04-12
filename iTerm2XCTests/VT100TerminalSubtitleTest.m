#import <XCTest/XCTest.h>
#import "VT100Terminal.h"

@interface VT100Terminal (TestingExposure)
- (NSString *)subtitleFromIconTitle:(NSString *)title;
@end

@interface VT100TerminalSubtitleTest : XCTestCase
@property (nonatomic) VT100Terminal *terminal;
@end

@implementation VT100TerminalSubtitleTest

- (void)setUp {
    [super setUp];
    _terminal = [[VT100Terminal alloc] init];
}

#pragma mark - subtitleFromIconTitle:

- (void)testSubtitleFromIconTitle_NoNewline {
    XCTAssertNil([_terminal subtitleFromIconTitle:@"just a title"]);
}

- (void)testSubtitleFromIconTitle_SimpleNewline {
    NSString *result = [_terminal subtitleFromIconTitle:@"title\nsubtitle"];
    XCTAssertEqualObjects(result, @"subtitle");
}

- (void)testSubtitleFromIconTitle_CrLfSplit {
    NSString *result = [_terminal subtitleFromIconTitle:@"title\r\nsubtitle"];
    XCTAssertEqualObjects(result, @"subtitle");
}

- (void)testSubtitleFromIconTitle_MultipleCrLfAtSplitPoint {
    NSString *result = [_terminal subtitleFromIconTitle:@"title\r\n\r\nsubtitle"];
    XCTAssertEqualObjects(result, @"subtitle");
}

- (void)testSubtitleFromIconTitle_EndsWithNewline {
    XCTAssertNil([_terminal subtitleFromIconTitle:@"title\n"]);
}

- (void)testSubtitleFromIconTitle_OnlyNewline {
    XCTAssertNil([_terminal subtitleFromIconTitle:@"\n"]);
}

- (void)testSubtitleFromIconTitle_EmptyString {
    XCTAssertNil([_terminal subtitleFromIconTitle:@""]);
}

- (void)testSubtitleFromIconTitle_MultipleLines {
    NSString *result = [_terminal subtitleFromIconTitle:@"title\nline1\nline2"];
    XCTAssertEqualObjects(result, @"line1\nline2");
}

- (void)testSubtitleFromIconTitle_CrStrippedFromSubtitle {
    NSString *result = [_terminal subtitleFromIconTitle:@"title\nfoo\rbar"];
    XCTAssertEqualObjects(result, @"foobar");
}

- (void)testSubtitleFromIconTitle_MultipleLinesWithCrLn {
    // Simulates TTY onlcr: each \n becomes \r\n
    NSString *result = [_terminal subtitleFromIconTitle:@"title\r\nline1\r\nline2"];
    XCTAssertEqualObjects(result, @"line1\nline2");
}

- (void)testSubtitleFromIconTitle_OnlyCrLf {
    XCTAssertNil([_terminal subtitleFromIconTitle:@"\r\n"]);
}

- (void)testSubtitleFromIconTitle_OnlyMultipleCrLf {
    XCTAssertNil([_terminal subtitleFromIconTitle:@"\r\n\r\n"]);
}

@end
