//
//  KLineChart.m
//  GGCharts
//
//  Created by 黄舜 on 17/7/4.
//  Copyright © 2017年 I really is a farmer. All rights reserved.
//

#import "KLineChart.h"
#import "GGChartDefine.h"
#import "NSArray+Stock.h"
#import "CrissCrossQueryView.h"

#import "MALayer.h"
#import "MAVOLLayer.h"
#import "EMALayer.h"
#import "BBIIndexLayer.h"
#import "BOLLLayer.h"

#import "MACDLayer.h"
#import "KDJLayer.h"
#import "MIKELayer.h"
#import "RSILayer.h"
#import "ATRLayer.h"

#import "NSObject+FireBlock.h"

#define FONT_ARIAL	@"ArialMT"

@interface KLineChart () <UIGestureRecognizerDelegate>

@property (nonatomic, strong) DKLineScaler * kLineScaler;   ///< 定标器

@property (nonatomic, strong) CAShapeLayer * greenLineLayer;    ///< 绿色k线
@property (nonatomic, strong) CAShapeLayer * redLineLayer;      ///< 红色K线

@property (nonatomic, strong) GGGridRenderer * kLineGrid;       ///< k线网格渲染器
@property (nonatomic, strong) GGGridRenderer * volumGrid;       ///< k线网格渲染器

@property (nonatomic, strong) GGAxisRenderer * axisRenderer;        ///< 轴渲染
@property (nonatomic, strong) GGAxisRenderer * kAxisRenderer;       ///< K线轴
@property (nonatomic, strong) GGAxisRenderer * vAxisRenderer;       ///< 成交量轴

@property (nonatomic, strong) CrissCrossQueryView * queryPriceView;     ///< 查价层

#pragma mark - 缩放手势

@property (nonatomic, assign) CGFloat currentZoom;  ///< 当前缩放比例
@property (nonatomic, assign) CGFloat zoomCenterSpacingLeft;    ///< 缩放中心K线位置距离左边的距离
@property (nonatomic, assign) NSUInteger zoomCenterIndex;     ///< 中心点k线

#pragma mark - 滑动手势

@property (nonatomic, assign) CGPoint lastPanPoint;     ///< 最后滑动的点
@property (nonatomic, assign) BOOL respondPanRecognizer;       ///< 是否相应滑动手势

@property (nonatomic, assign) BOOL disPlay;

#pragma mark - 指标

@property (nonatomic, strong) BaseIndexLayer * kLineIndexLayer;
@property (nonatomic, strong) BaseIndexLayer * volumIndexLayer;

@property (nonatomic, strong) UILabel * lableKLineIndex;
@property (nonatomic, strong) UILabel * lableVolumIndex;

@end

@implementation KLineChart

+ (NSArray *)kLineIndexLayerClazz
{
    return @[[MALayer class],
             [EMALayer class],
             [MIKELayer class],
             [BOLLLayer class],
             [BBIIndexLayer class]];
}

+ (NSArray *)kVolumIndexLayerClazz
{
    return @[[MAVOLLayer class],
             [MACDLayer class],
             [KDJLayer class],
             [RSILayer class],
             [ATRLayer class]];
}

#pragma mark - Surper

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
    if (self) {
        
        _disPlay = YES;
        _kLineIndexIndex = 0;
        _volumIndexIndex = 0;
        
        [self.scrollView.layer addSublayer:self.redLineLayer];
        [self.scrollView.layer addSublayer:self.greenLineLayer];
        
        self.volumGrid.width = 0.25;
        [self.kLineBackLayer addRenderer:self.volumGrid];
        self.kLineGrid.width = 0.25;
        [self.kLineBackLayer addRenderer:self.kLineGrid];
        self.axisRenderer.width = 0.25;
        [self.kLineBackLayer addRenderer:self.axisRenderer];
        
        self.kAxisRenderer.width = 0.25;
        [self.stringLayer addRenderer:self.kAxisRenderer];
        self.vAxisRenderer.width = 0.25;
        [self.stringLayer addRenderer:self.vAxisRenderer];
        
        [self addSubview:self.lableVolumIndex];
        [self addSubview:self.lableKLineIndex];
        
        _kAxisSplit = 7;
        _kInterval = 3;
        _kLineCountVisibale = 60;
        _kMaxCountVisibale = 120;
        _kMinCountVisibale = 20;
        _axisFont = [UIFont fontWithName:FONT_ARIAL size:10];
        _riseColor = RGB(234, 82, 83);
        _fallColor = RGB(77, 166, 73);
        _gridColor = RGB(225, 225, 225);
        _axisStringColor = C_HEX(0xaeb1b6);
        _currentZoom = -.001f;
        
        self.lableKLineIndex.font = [UIFont fontWithName:FONT_ARIAL size:8.5];
        self.lableVolumIndex.font = [UIFont fontWithName:FONT_ARIAL size:8.5];
        
        self.queryPriceView.frame = CGRectMake(0, 0, frame.size.width, frame.size.height);
        [self addSubview:self.queryPriceView];
        
        UIPinchGestureRecognizer * pinchGestureRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchesViewOnGesturer:)];
        [self addGestureRecognizer:pinchGestureRecognizer];
        
        UILongPressGestureRecognizer * longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressViewOnGesturer:)];
        [self addGestureRecognizer:longPress];
        
        UITapGestureRecognizer * tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(touchIndexLayer:)];
        [self addGestureRecognizer:tapRecognizer];
    }
    
    return self;
}

/** 成交量是否为红 */
- (BOOL)volumIsRed:(id)obj
{
    return [self isRed:obj];
}

/** k线是否为红 */
- (BOOL)isRed:(id <KLineAbstract>)kLineObj
{
    return kLineObj.ggOpen >= kLineObj.ggClose;
}

/**
 * 视图滚动
 */
- (void)scrollViewContentSizeDidChange
{
    [super scrollViewContentSizeDidChange];
    
    [self updateSubLayer];
}

- (void)setFrame:(CGRect)frame
{
    [super setFrame:frame];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [self scrollViewContentSizeDidChange];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    CGFloat minMove = self.kLineScaler.shapeWidth + self.kLineScaler.shapeInterval;
    self.scrollView.contentOffset = CGPointMake(round(self.scrollView.contentOffset.x / minMove) * minMove, 0);
    
    [self scrollViewContentSizeDidChange];
}

#pragma mark - K线手势

- (void)longPressViewOnGesturer:(UILongPressGestureRecognizer *)recognizer
{
    self.scrollView.scrollEnabled = NO;
    
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        
        [self updateSubLayer];
        
        self.scrollView.scrollEnabled = YES;
        self.queryPriceView.hidden = YES;
        [self.queryPriceView clearLine];
    }
    else if (recognizer.state == UIGestureRecognizerStateBegan) {
        
        CGPoint velocity = [recognizer locationInView:self];
        [self updateQueryLayerWithPoint:velocity];
        self.queryPriceView.hidden = NO;
    }
    else if (recognizer.state == UIGestureRecognizerStateChanged) {
        
        CGPoint velocity = [recognizer locationInView:self];
        [self updateQueryLayerWithPoint:velocity];
    }
}

- (void)updateQueryLayerWithPoint:(CGPoint)velocity
{
    CGPoint velocityInScroll = [self.scrollView convertPoint:velocity fromView:self.queryPriceView];
    NSInteger index = [self pointConvertIndex:velocityInScroll.x];
    id <KLineAbstract, QueryViewAbstract> kData = self.kLineArray[index];
    
    NSString * yString = @"";
    
    self.queryPriceView.xAxisOffsetY = self.redLineLayer.gg_bottom;
    
    if (CGRectContainsPoint(self.redLineLayer.frame, velocity)) {
        
        yString = [NSString stringWithFormat:@"%.2f", [self.kLineScaler getPriceWithPoint:CGPointMake(0, velocity.y - self.redLineLayer.gg_top - self.queryPriceView.lineWidth)]];
    }
    else if (CGRectContainsPoint(self.redVolumLayer.frame, velocity)) {
        
        NSString * string = self.redVolumLayer.hidden ? @"" : @"万手";
        
        yString = [NSString stringWithFormat:@"%.2f%@", [self.volumScaler getPriceWithPoint:CGPointMake(0, velocity.y - self.queryPriceView.lineWidth - self.redVolumLayer.gg_top)], string];
    }
    
    [self updateIndexStringForIndex:index];
    
    NSString * title = [self getDateString:kData.ggKLineDate];
    [self.queryPriceView setYString:yString setXString:title];
    [self.queryPriceView.queryView setQueryData:kData];
    
    GGKShape shape = self.kLineScaler.kShapes[index];
    CGPoint queryVelocity = [self.scrollView convertPoint:shape.top toView:self.queryPriceView];
    [self.queryPriceView setCenterPoint:CGPointMake(queryVelocity.x, velocity.y)];
}

- (NSString *)getDateString:(NSDate *)date
{
    NSDateFormatter * showFormatter = [[NSDateFormatter alloc] init];
    showFormatter.dateFormat = @"yyyy-MM-dd";
    return [showFormatter stringFromDate:date];
}

/** 获取点对应的数据 */
- (NSInteger)pointConvertIndex:(CGFloat)x
{
    NSInteger idx = x / (self.kLineScaler.shapeWidth + self.kLineScaler.shapeInterval);
    return idx >= self.kLineScaler.kLineObjAry.count ? self.kLineScaler.kLineObjAry.count - 1 : idx;
}

-(void)pinchesViewOnGesturer:(UIPinchGestureRecognizer *)recognizer
{
    self.scrollView.scrollEnabled = NO;     // 放大禁用滚动手势
    
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        
        _currentZoom = recognizer.scale;
        
        self.scrollView.scrollEnabled = YES;
    }
    else if (recognizer.state == UIGestureRecognizerStateBegan && _currentZoom != 0.0f) {
        
        recognizer.scale = _currentZoom;
        
        CGPoint touch1 = [recognizer locationOfTouch:0 inView:self];
        CGPoint touch2 = [recognizer locationOfTouch:1 inView:self];
        
        // 放大开始记录位置等数据
        CGFloat center_x = (touch1.x + touch2.x) / 2.0f;
        _zoomCenterIndex = [self pointConvertIndex:self.scrollView.contentOffset.x + center_x];
        GGKShape shape = self.kLineScaler.kShapes[_zoomCenterIndex];
        _zoomCenterSpacingLeft = shape.top.x - self.scrollView.contentOffset.x;
    }
    else if (recognizer.state == UIGestureRecognizerStateChanged) {
        
        CGFloat tmpZoom;
        tmpZoom = recognizer.scale / _currentZoom;
        _currentZoom = recognizer.scale;
        NSInteger showNum = round(_kLineCountVisibale / tmpZoom);
        
        // 避免没必要计算
        if (showNum == _kLineCountVisibale) { return; }
        if (showNum >= _kLineCountVisibale && _kLineCountVisibale == _kMaxCountVisibale) return;
        if (showNum <= _kLineCountVisibale && _kLineCountVisibale == _kMinCountVisibale) return;
        
        // 极大值极小值
        _kLineCountVisibale = showNum;
        _kLineCountVisibale = _kLineCountVisibale < 20 ? 20 : _kLineCountVisibale;
        _kLineCountVisibale = _kLineCountVisibale > 120 ? 120 : _kLineCountVisibale;
        
        [self kLineSubLayerRespond];
        
        GGKShape shape = self.kLineScaler.kShapes[_zoomCenterIndex];
        CGFloat offsetX = shape.top.x - _zoomCenterSpacingLeft;
        
        if (offsetX < 0) { offsetX = 0; }
        if (offsetX > self.scrollView.contentSize.width - self.scrollView.frame.size.width) {
            offsetX = self.scrollView.contentSize.width - self.scrollView.frame.size.width;
        }
        
        self.scrollView.contentOffset = CGPointMake(offsetX, 0);
    }
}

- (void)touchIndexLayer:(UILongPressGestureRecognizer *)recognizer
{
    CGPoint velocity = [recognizer locationInView:self];
    CGPoint velocityInScroll = [self.scrollView convertPoint:velocity fromView:self.queryPriceView];
    
    if (CGRectContainsPoint(self.greenLineLayer.frame, velocityInScroll)) {
        
        _kLineIndexIndex++;
        
        if (_kLineIndexIndex > [[KLineChart kLineIndexLayerClazz] count] - 1) {
            
            _kLineIndexIndex = 0;
        }
        
        [self updateKLineIndexLayer:_kLineIndexIndex];
    }
    
    if (CGRectContainsPoint(self.volumIndexLayer.frame, velocityInScroll)) {
        
        _volumIndexIndex++;
        
        if (_volumIndexIndex > [[KLineChart kVolumIndexLayerClazz] count] - 1) {
            
            _volumIndexIndex = 0;
        }
        
        [self updateVolumIndexLayer:_volumIndexIndex];
    }
}

- (void)updateVolumIndexLayer:(NSInteger)index
{
    runMainThreadWithBlock(^{
        
        [_volumIndexLayer removeFromSuperlayer];
        
        Class clazz = [KLineChart kVolumIndexLayerClazz][index];
        
        _volumIndexLayer = [[clazz alloc] init];
        _volumIndexLayer.frame = self.redVolumLayer.frame;
        [_volumIndexLayer setKLineArray:_kLineArray];
        [self.scrollView.layer addSublayer:_volumIndexLayer];
        
        [self updateSubLayer];
    });
}

- (void)updateKLineIndexLayer:(NSInteger)index
{
    runMainThreadWithBlock(^{
        
        [_kLineIndexLayer removeFromSuperlayer];
        
        Class clazz = [KLineChart kLineIndexLayerClazz][index];
        
        _kLineIndexLayer = [[clazz alloc] init];
        _kLineIndexLayer.frame = self.redLineLayer.frame;
        [_kLineIndexLayer setKLineArray:_kLineArray];
        [self.scrollView.layer addSublayer:_kLineIndexLayer];
        
        [self updateSubLayer];
    });
}

#pragma mark - Setter

/** 设置k线方法 */
- (void)setKLineArray:(NSArray<id<KLineAbstract, VolumeAbstract, QueryViewAbstract>> *)kLineArray
{
    _kLineArray = kLineArray;
    
    [_kLineIndexLayer setKLineArray:kLineArray];
    
    [_volumIndexLayer setKLineArray:kLineArray];
    
    [self.kLineScaler setObjArray:kLineArray
                          getOpen:@selector(ggOpen)
                         getClose:@selector(ggClose)
                          getHigh:@selector(ggHigh)
                           getLow:@selector(ggLow)];
}

#pragma mark - 更新视图

- (void)updateChart
{
    [self baseConfigRendererAndLayer];
    
    [self kLineSubLayerRespond];
    [self updateKLineIndexLayer:_kLineIndexIndex];
    [self updateVolumIndexLayer:_volumIndexIndex];
}

- (void)kLineSubLayerRespond
{
    [self baseConfigKLineLayer];
    [self baseConfigVolumLayer];
    
    [self updateSubLayer];
    [self updateKLineGridLayerRenderders];
}

- (void)updateIndexStringForIndex:(NSInteger)index
{
    self.lableVolumIndex.attributedText = [self.volumIndexLayer attrStringWithIndex:index];
    self.lableKLineIndex.attributedText = [self.kLineIndexLayer attrStringWithIndex:index];
}

#pragma mark - rect

#define INDEX_STRING_INTERVAL   12
#define KLINE_VOLUM_INTERVAL    15

- (CGRect)kLineFrame
{
    return CGRectMake(0, INDEX_STRING_INTERVAL, self.frame.size.width, self.frame.size.height * .6f - INDEX_STRING_INTERVAL);
}

- (CGRect)volumFrame
{
    CGFloat highKLine = self.kLineFrame.size.height;
    CGFloat volumTop = INDEX_STRING_INTERVAL * 2 + highKLine + KLINE_VOLUM_INTERVAL;
    
    return CGRectMake(0, volumTop, self.redLineLayer.gg_width, self.frame.size.height - volumTop);
}

#pragma mark - 基础设置层

/** K线 */
- (void)baseConfigKLineLayer
{
    self.redLineLayer.frame = self.kLineFrame;
    self.kLineScaler.rect = CGRectMake(0, 0, self.redLineLayer.gg_width, self.redLineLayer.gg_height);
    self.kLineScaler.shapeWidth = self.kLineScaler.rect.size.width / _kLineCountVisibale - _kInterval;
    self.kLineScaler.shapeInterval = _kInterval;
    
    CGSize contentSize = self.kLineScaler.contentSize;
    
    // 设置滚动位置关闭隐士动画
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    self.kLineBackLayer.frame = CGRectMake(0, 0, contentSize.width, self.frame.size.height);
    
    // 滚动大小
    self.scrollView.contentSize = contentSize;
    self.backScrollView.contentSize = contentSize;
    
    // K线与K线指标大小
    self.redLineLayer.gg_size = contentSize;
    self.greenLineLayer.frame = self.redLineLayer.frame;
    self.kLineIndexLayer.frame = self.redLineLayer.frame;
    
    self.lableKLineIndex.frame = CGRectMake(0, 0, self.gg_width, INDEX_STRING_INTERVAL);
    self.queryPriceView.frame = CGRectMake(0, self.redLineLayer.gg_top, self.gg_width, self.gg_height - self.redLineLayer.gg_top);
    [CATransaction commit];
}

/** 成交量 */
- (void)baseConfigVolumLayer
{
    CGRect volumRect = self.volumFrame;
    
    [self setVolumRect:volumRect];
    self.volumScaler.rect = CGRectMake(0, 0, self.redVolumLayer.gg_width, self.redVolumLayer.gg_height);
    self.volumScaler.barWidth = self.kLineScaler.shapeWidth;
    [self.volumScaler setObjAry:_kLineArray getSelector:@selector(ggVolume)];
    
    self.lableVolumIndex.frame = CGRectMake(0, self.redLineLayer.gg_bottom + KLINE_VOLUM_INTERVAL, self.gg_width, INDEX_STRING_INTERVAL);
    
    // 量能区域的指标
    _volumIndexLayer.frame = volumRect;
}

/** 设置渲染器 */
- (void)baseConfigRendererAndLayer
{
    // 成交量颜色设置
    self.redVolumLayer.strokeColor = _riseColor.CGColor;
    self.redVolumLayer.fillColor = _riseColor.CGColor;
    
    self.greenVolumLayer.strokeColor = _fallColor.CGColor;
    self.greenVolumLayer.fillColor = _fallColor.CGColor;
    
    // k线图颜色设置
    self.redLineLayer.strokeColor = _riseColor.CGColor;
    self.redLineLayer.fillColor = _riseColor.CGColor;
    
    self.greenLineLayer.strokeColor = _fallColor.CGColor;
    self.greenLineLayer.fillColor = _fallColor.CGColor;
    
    // 成交量网格设置
    self.volumGrid.color = _gridColor;
    
    // 成交量Y轴设置
    self.vAxisRenderer.strColor = _axisStringColor;
    self.vAxisRenderer.showLine = NO;
    self.vAxisRenderer.strFont = _axisFont;
    self.vAxisRenderer.offSetRatio = CGPointMake(0, -1);
    
    // K线Y轴设置
    self.kAxisRenderer.strColor = _axisStringColor;
    self.kAxisRenderer.showLine = NO;
    self.kAxisRenderer.strFont = _axisFont;
    self.kAxisRenderer.offSetRatio = CGPointMake(0, -1);
    
    // X横轴设置
    self.axisRenderer.strColor = _axisStringColor;
    self.axisRenderer.showLine = NO;
    self.axisRenderer.strFont = _axisFont;
    
    // K线网格设置
    self.kLineGrid.color = _gridColor;
}

/** 更新k线背景层 */
- (void)updateKLineGridLayerRenderders
{
    // 纵向分割高度
    CGFloat v_spe = self.redLineLayer.gg_height / _kAxisSplit;
    __weak KLineChart * weakSelf = self;
    
    // 成交量网格设置
    self.volumGrid.grid = GGGridRectMake(self.redVolumLayer.frame, v_spe, 0);
    
    // 成交量Y轴设置
    GGLine leftLine = GGLeftLineRect(self.redVolumLayer.frame);
    self.vAxisRenderer.axis = GGAxisLineMake(leftLine, 0, v_spe);
    [self.vAxisRenderer setStringBlock:^NSString *(CGPoint point, NSInteger index, NSInteger max) {
        if (index == 0) { return @""; }
        point.y = point.y - weakSelf.redVolumLayer.gg_top;
        NSString * string = weakSelf.redVolumLayer.hidden ? @"" : @"万手";
        return [NSString stringWithFormat:@"%.2f%@", [weakSelf.volumScaler getPriceWithPoint:point], string];
    }];
    
    // K线Y轴设置
    leftLine = GGLeftLineRect(self.redLineLayer.frame);
    self.kAxisRenderer.axis = GGAxisLineMake(leftLine, 0, GGLengthLine(leftLine) / _kAxisSplit);
    [self.kAxisRenderer setStringBlock:^NSString *(CGPoint point, NSInteger index, NSInteger max) {
        if (index == 0) { return @""; }
        point.y = point.y - weakSelf.redLineLayer.gg_top;
        return [NSString stringWithFormat:@"%.2f", [weakSelf.kLineScaler getPriceWithPoint:point]];
    }];
    
    // X横轴设置
    self.axisRenderer.axis = GGAxisLineMake(GGBottomLineRect(self.greenLineLayer.frame), 1.5, 0);
    
    // K线网格设置
    [self.kLineGrid removeAllLine];
    self.kLineGrid.grid = GGGridRectMake(self.redLineLayer.frame, v_spe, 0);
    
    [_kLineArray enumerateObjectsUsingBlock:^(id<KLineAbstract,VolumeAbstract, QueryViewAbstract> obj, NSUInteger idx, BOOL * stop) {
        
        if ([obj isShowTitle]) {
            
            CGFloat x = self.kLineScaler.kShapes[idx].top.x;
            [self.axisRenderer addString:obj.ggKLineTitle point:CGPointMake(x, CGRectGetMaxY(self.greenLineLayer.frame))];
            
            if (idx == 0) { return; }
            
            GGLine kline = [self lineWithX:x rect:self.greenLineLayer.frame];
            GGLine vline = [self lineWithX:x rect:self.redVolumLayer.frame];
            [self.kLineGrid addLine:kline];
            [self.kLineGrid addLine:vline];
        }
    }];
    
    [self.kLineBackLayer setNeedsDisplay];
}

- (GGLine)lineWithX:(CGFloat)x rect:(CGRect)rect
{
    return GGLineMake(x, CGRectGetMinY(rect), x, CGRectGetMaxY(rect));
}

#pragma mark - 实时更新

- (void)updateSubLayer
{
    // 计算显示的在屏幕中的k线
    NSInteger index = (self.scrollView.contentOffset.x - self.kLineScaler.rect.origin.x) / (self.kLineScaler.shapeInterval + self.kLineScaler.shapeWidth);
    NSInteger len = _kLineCountVisibale;
    
    if (index < 0) index = 0;
    if (index > _kLineArray.count) index = _kLineArray.count;
    if (index + _kLineCountVisibale > _kLineArray.count) { len = _kLineArray.count - index; }
    
    NSRange range = NSMakeRange(index, len);
    
    // 更新视图
    [self updateKLineLayerWithRange:range];
    [self updateVolumLayerWithRange:range];
    
    [self updateIndexStringForIndex:NSMaxRange(range) - 1];
}

/** K线图实时更新 */
- (void)updateKLineLayerWithRange:(NSRange)range
{
    // 计算k线最大最小
    CGFloat max = FLT_MIN;
    CGFloat min = FLT_MAX;
    [_kLineArray getKLineMax:&max min:&min range:range];
    
    // k线指标
    [_kLineIndexLayer getIndexWithRange:range max:&max min:&min];
    [_kLineIndexLayer updateLayerWithRange:range max:max min:min];
    
    // 更新k线层
    self.kLineScaler.max = max;
    self.kLineScaler.min = min;
    [self.kLineScaler updateScaler];
    
    CGMutablePathRef refRed = CGPathCreateMutable();
    CGMutablePathRef refGreen = CGPathCreateMutable();
    
    for (NSUInteger i = range.location; i < range.location + range.length; i++) {
        
        id obj = _kLineArray[i];
        GGKShape shape = self.kLineScaler.kShapes[i];
        
        [self isRed:obj] ? GGPathAddKShape(refRed, shape) : GGPathAddKShape(refGreen, shape);
    }
    
    self.redLineLayer.path = refRed;
    CGPathRelease(refRed);
    self.greenLineLayer.path = refGreen;
    CGPathRelease(refGreen);
    
    [self.stringLayer setNeedsDisplay];
}

/** 柱状图实时更新 */
- (void)updateVolumLayerWithRange:(NSRange)range
{
    self.redVolumLayer.hidden = ![self.volumIndexLayer isKindOfClass:[MAVOLLayer class]];
    self.greenVolumLayer.hidden = ![self.volumIndexLayer isKindOfClass:[MAVOLLayer class]];
    
    // 计算柱状图最大最小
    CGFloat max = FLT_MIN;
    CGFloat min = FLT_MAX;
    NSString * attached = @"";
    
    if ([self.volumIndexLayer isKindOfClass:[MAVOLLayer class]]) {
        
        [_kLineArray getMax:&max min:&min selGetter:@selector(ggVolume) range:range base:0.1];
        min = 0;
        attached = @"万手";
    }
    
    [self.volumIndexLayer getIndexWithRange:range max:&max min:&min];
    [self.volumIndexLayer updateLayerWithRange:range max:max min:min];
    
    // 更新成交量
    self.volumScaler.min = 0;
    self.volumScaler.max = max;
    [self.volumScaler updateScaler];
    [self updateVolumLayer:range];
    
    [self.stringLayer setNeedsDisplay];
}

#pragma mark - Lazy

GGLazyGetMethod(CAShapeLayer, redLineLayer);
GGLazyGetMethod(CAShapeLayer, greenLineLayer);

GGLazyGetMethod(UILabel, lableKLineIndex);
GGLazyGetMethod(UILabel, lableVolumIndex);

GGLazyGetMethod(GGGridRenderer, kLineGrid);
GGLazyGetMethod(GGGridRenderer, volumGrid);

GGLazyGetMethod(GGAxisRenderer, axisRenderer);
GGLazyGetMethod(GGAxisRenderer, kAxisRenderer);
GGLazyGetMethod(GGAxisRenderer, vAxisRenderer);

GGLazyGetMethod(DKLineScaler, kLineScaler);

GGLazyGetMethod(CrissCrossQueryView, queryPriceView);

@end