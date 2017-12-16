//
//  SJCTFrameParser.m
//  Test
//
//  Created by BlueDancer on 2017/12/13.
//  Copyright © 2017年 SanJiang. All rights reserved.
//

#import "SJCTFrameParser.h"
#import "SJCTData.h"
#import "SJCTImageData.h"
#import "SJCTLinkData.h"
#import "SJCTFrameParserConfig.h"
#import <CoreText/CoreText.h>

typedef NSString * NSAttributedStringKey NS_EXTENSIBLE_STRING_ENUM;

@implementation SJCTFrameParser

+ (NSDictionary *)_attributesWithConfig:(SJCTFrameParserConfig *)config {
    CTFontRef fontRef = CTFontCreateWithName((CFStringRef)config.font.fontName, [SJCTFrameParserConfig fontSize:config.font], NULL);
    CGFloat lineSpacing = config.lineSpacing;
    CTTextAlignment textAlignment = kCTTextAlignmentLeft;
    switch ( config.textAlignment ) {
        case NSTextAlignmentRight: {
            textAlignment = kCTTextAlignmentRight;
        }
            break;
        case NSTextAlignmentCenter: {
            textAlignment = kCTTextAlignmentCenter;
        }
            break;
        default: {
            textAlignment = (CTTextAlignment)config.textAlignment;
        }
            break;
    }
    const size_t _kNumberOfSettings = 4;
    CTParagraphStyleSetting paragraphStyleSettings[_kNumberOfSettings] = {
        { kCTParagraphStyleSpecifierLineSpacingAdjustment, sizeof(CGFloat), &lineSpacing },
        { kCTParagraphStyleSpecifierMaximumLineSpacing, sizeof(CGFloat), &lineSpacing },
        { kCTParagraphStyleSpecifierMinimumLineSpacing, sizeof(CGFloat), &lineSpacing},
        { kCTParagraphStyleSpecifierAlignment, sizeof(CTTextAlignment), &textAlignment}
    };
//    kCTTextAlignmentLeft      = 0,
//    kCTTextAlignmentRight     = 1,
//    kCTTextAlignmentCenter    = 2,
//    kCTTextAlignmentJustified = 3,
//    kCTTextAlignmentNatural   = 4,
//    NSTextAlignmentLeft      = 0,    // Visually left aligned
//#if TARGET_OS_IPHONE
//    NSTextAlignmentCenter    = 1,    // Visually centered
//    NSTextAlignmentRight     = 2,    // Visually right aligned
//#else /* !TARGET_OS_IPHONE */
//    NSTextAlignmentRight     = 1,    // Visually right aligned
//    NSTextAlignmentCenter    = 2,    // Visually centered
//#endif
//    NSTextAlignmentJustified = 3,    // Fully-justified. The last line in a paragraph is natural-aligned.
//    NSTextAlignmentNatural   = 4,    // Indicates the default alignment for script

    CTParagraphStyleRef paragraphRef = CTParagraphStyleCreate(paragraphStyleSettings, _kNumberOfSettings);
    
    UIColor *textColor = config.textColor;
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[(id)kCTForegroundColorAttributeName] = (__bridge id _Nullable)textColor.CGColor;
    dict[(id)kCTFontAttributeName] = (__bridge id _Nullable)(fontRef);
    dict[(id)kCTParagraphStyleAttributeName] = (__bridge id)paragraphRef;
    
    CFRelease(paragraphRef);
    CFRelease(fontRef);
    return dict;
}

+ (SJCTData *)parserContent:(NSString *)content config:(SJCTFrameParserConfig *)config {
    NSDictionary *attributes = [self _attributesWithConfig:config];
    NSAttributedString *attrStr = [[NSAttributedString alloc] initWithString:content attributes:attributes];
    return [self parserAttributedStr:attrStr config:config];
}

+ (SJCTData *)parserAttributedStr:(NSAttributedString *)attrStr config:(SJCTFrameParserConfig *)config {
    NSMutableAttributedString *attrStrM = attrStr.mutableCopy;
    NSArray<SJCTImageData *> *imageDataArray =
    [self _findingImageDataWithAttrStr:attrStr findingBlock:^(NSRange range, NSTextAttachment *attachment) {
        [attrStrM replaceCharactersInRange:range withAttributedString:[self _replaceWithAttachment:attachment config:config]];
    }];
    
    NSArray<SJCTLinkData *> *linkDataArray = [self _findingLinkURLWithAttributedString:attrStr];
    
    CTFramesetterRef framesetterRef =
    CTFramesetterCreateWithAttributedString((CFAttributedStringRef)attrStrM);
    
    CGFloat width = config.maxWidth;
    CGFloat height = [self _contentHeightWithFramesetter:framesetterRef width:width];
    
    CTFrameRef frameRef = [self _createFrameRefWithFramesetter:framesetterRef constraints:CGSizeMake(width, height)];
    
    [self _findingImagesPositionWithFrameRef:frameRef imagesDataArrary:imageDataArray];
    
    SJCTData *ctdata = [SJCTData new];
    ctdata.frameRef = frameRef;
    ctdata.height = height;
    ctdata.imageDataArray = imageDataArray;
    ctdata.linkDataArray = linkDataArray;
    
    CFRelease(frameRef);
    return ctdata;
}

+ (CTFrameRef)_createFrameRefWithFramesetter:(CTFramesetterRef)framesetterRef constraints:(CGSize)size {
    CGRect rect = (CGRect){CGPointZero, size};
    CGMutablePathRef pathM = CGPathCreateMutable();
    CGPathAddRect(pathM, NULL, rect);
    
    CTFrameRef frameRef = CTFramesetterCreateFrame(framesetterRef,
                                                   CFRangeMake(0, 0),
                                                   pathM,
                                                   NULL);
    if ( pathM ) CFRelease(pathM);
    return frameRef;
}

#pragma mark -
+ (NSArray<SJCTImageData *> *)_findingImageDataWithAttrStr:(NSAttributedString *)content findingBlock:(void(^)(NSRange range, NSTextAttachment *attachment))block {
    NSMutableArray<SJCTImageData *> *imageDataArrayM = [NSMutableArray new];
    [content enumerateAttributesInRange:NSMakeRange(0, content.length) options:NSAttributedStringEnumerationReverse usingBlock:^(NSDictionary<NSAttributedStringKey,id> * _Nonnull attrs, NSRange range, BOOL * _Nonnull stop) {
        NSTextAttachment *attachment = attrs[NSAttachmentAttributeName];
        if ( ! attachment ) return;
        SJCTImageData *imageData = [SJCTImageData new];
        imageData.imageAttachment = attachment;
        imageData.postion = (int)(range.length);
        [imageDataArrayM addObject:imageData];
        block(range, attachment);
    }];
    return imageDataArrayM;
}

+ (NSArray<SJCTLinkData *> *)_findingLinkURLWithAttributedString:(NSAttributedString *)attrStr {
    NSMutableArray<SJCTLinkData *> *linkDataArrM = [NSMutableArray new];
    [attrStr enumerateAttributesInRange:NSMakeRange(0, attrStr.length) options:NSAttributedStringEnumerationLongestEffectiveRangeNotRequired usingBlock:^(NSDictionary<NSAttributedStringKey,id> * _Nonnull attrs, NSRange range, BOOL * _Nonnull stop) {
        id value = attrs[NSLinkAttributeName];
        if ( value ) {
            SJCTLinkData *linkData = [SJCTLinkData new];
            linkData.URLStr = [attrStr attributedSubstringFromRange:range].string;
            linkData.range = range;
            [linkDataArrM addObject:linkData];
        }
    }];
    return linkDataArrM;
}

+ (void)_findingImagesPositionWithFrameRef:(CTFrameRef)frameRef
                   imagesDataArrary:(NSArray<SJCTImageData *> *)imageDataArray {
    
    if ( 0 == imageDataArray.count ) return;
    
    NSArray *lines = (NSArray *)CTFrameGetLines(frameRef);
    NSUInteger lineCount = [lines count];
    CGPoint lineOrigins[lineCount];
    CTFrameGetLineOrigins(frameRef, CFRangeMake(0, 0), lineOrigins);
    
    int imgIndex = 0;
    SJCTImageData *imageData = imageDataArray[0];
    
    for ( int i = 0; i < lineCount; ++i ) {
        if ( imageData == nil ) { break; }
        
        CTLineRef line = (__bridge CTLineRef)lines[i];
        NSArray * runObjArray = (NSArray *)CTLineGetGlyphRuns(line);
        for ( id runObj in runObjArray ) {
            
            CTRunRef run = (__bridge CTRunRef)runObj;
            NSDictionary *runAttributes = (NSDictionary *)CTRunGetAttributes(run);
            CTRunDelegateRef delegate = (__bridge CTRunDelegateRef)[runAttributes valueForKey:(id)kCTRunDelegateAttributeName];
            
            if ( NULL == delegate ) { continue;}
            
            if ( ![(id)CTRunDelegateGetRefCon(delegate) isKindOfClass:[NSTextAttachment class]] ) { continue;}
            
            CGRect runBounds = [self _runBoundsWithLine:line run:run offset:lineOrigins[i]];
            
            CGPathRef pathRef = CTFrameGetPath(frameRef);
            CGRect colRect = CGPathGetBoundingBox(pathRef);
            
            CGRect delegateBounds = CGRectOffset(runBounds,
                                                 colRect.origin.x,
                                                 colRect.origin.y);
            imageData.imagePosition = delegateBounds;
            
            imgIndex++;
            
            if ( imgIndex == imageDataArray.count ) {
                imageData = nil;
                break;
            }
            else {
                imageData = imageDataArray[imgIndex];
            }
        }
    }
}

+ (CGRect)_runBoundsWithLine:(CTLineRef)line
                         run:(CTRunRef)run
                      offset:(CGPoint)lineOffset {
    CGRect runBounds = CGRectZero;
    CGFloat ascent = 0;
    CGFloat descent = 0;
    runBounds.size.width = CTRunGetTypographicBounds(run,
                                                     CFRangeMake(0, 1),
                                                     &ascent,
                                                     &descent,
                                                     NULL);
    runBounds.size.height = ascent + descent;
    
    CGFloat xOffset = CTLineGetOffsetForStringIndex(line,
                                                    CTRunGetStringRange(run).location,
                                                    NULL);
    runBounds.origin.x = lineOffset.x + xOffset;
    runBounds.origin.y = lineOffset.y;
    runBounds.origin.y -= descent;
    return runBounds;
}

#pragma mark -
static CGFloat ascentCallback(void *ref){
    return [(__bridge NSTextAttachment *)ref bounds].size.height;
}

static CGFloat descentCallback(void *ref){
    return 0;
}

static CGFloat widthCallback(void* ref){
    return [(__bridge NSTextAttachment *)ref bounds].size.width;
}

+ (NSAttributedString *)_replaceWithAttachment:(NSTextAttachment *)attachment
                                          config:(SJCTFrameParserConfig *)config {
    CTRunDelegateCallbacks callbacks;
    memset(&callbacks, 0, sizeof(CTRunDelegateCallbacks));
    callbacks.version = kCTRunDelegateVersion1;
    callbacks.getAscent = ascentCallback;
    callbacks.getDescent = descentCallback;
    callbacks.getWidth = widthCallback;
    CTRunDelegateRef delegate = CTRunDelegateCreate(&callbacks, (__bridge void *)(attachment));
    
    unichar objectReplacementChar = 0xFFFC;
    NSString *content = [NSString stringWithCharacters:&objectReplacementChar length:1];
    NSDictionary *attributes = [self _attributesWithConfig:config];
    NSMutableAttributedString *space =
    [[NSMutableAttributedString alloc] initWithString:content attributes:attributes];
    CFAttributedStringSetAttribute((CFMutableAttributedStringRef)space,
                                   CFRangeMake(0, 1),
                                   kCTRunDelegateAttributeName,
                                   delegate);
    CFRelease(delegate);
    return space;
}

+ (CGFloat)_contentHeightWithFramesetter:(CTFramesetterRef)framesetter width:(CGFloat)maxWidth {
    CGSize constraints = CGSizeMake(maxWidth, CGFLOAT_MAX);
    CGSize contentSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0, 0), NULL, constraints, NULL);
    return contentSize.height;
}

@end
