//
//  XBHWDecoder.m
//

#import "XBHWDecoder.h"
#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVSampleBufferDisplayLayer.h>

void decompressionSessionDecodeFrameCallback(void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef imageBuffer, CMTime presentationTimeStamp, CMTime presentationDuration);

NSString * const naluTypesStrings[] =
{
    @"0: Unspecified (non-VCL)",
    @"1: Coded slice of a non-IDR picture (VCL)",    // P frame
    @"2: Coded slice data partition A (VCL)",
    @"3: Coded slice data partition B (VCL)",
    @"4: Coded slice data partition C (VCL)",
    @"5: Coded slice of an IDR picture (VCL)",      // I frame
    @"6: Supplemental enhancement information (SEI) (non-VCL)",
    @"7: Sequence parameter set (non-VCL)",         // SPS parameter
    @"8: Picture parameter set (non-VCL)",          // PPS parameter
    @"9: Access unit delimiter (non-VCL)",
    @"10: End of sequence (non-VCL)",
    @"11: End of stream (non-VCL)",
    @"12: Filler data (non-VCL)",
    @"13: Sequence parameter set extension (non-VCL)",
    @"14: Prefix NAL unit (non-VCL)",
    @"15: Subset sequence parameter set (non-VCL)",
    @"16: Reserved (non-VCL)",
    @"17: Reserved (non-VCL)",
    @"18: Reserved (non-VCL)",
    @"19: Coded slice of an auxiliary coded picture without partitioning (non-VCL)",
    @"20: Coded slice extension (non-VCL)",
    @"21: Coded slice extension for depth view components (non-VCL)",
    @"22: Reserved (non-VCL)",
    @"23: Reserved (non-VCL)",
    @"24: STAP-A Single-time aggregation packet (non-VCL)",
    @"25: STAP-B Single-time aggregation packet (non-VCL)",
    @"26: MTAP16 Multi-time aggregation packet (non-VCL)",
    @"27: MTAP24 Multi-time aggregation packet (non-VCL)",
    @"28: FU-A Fragmentation unit (non-VCL)",
    @"29: FU-B Fragmentation unit (non-VCL)",
    @"30: Unspecified (non-VCL)",
    @"31: Unspecified (non-VCL)",
};

#define pframeHeader 128

@interface XBHWDecoder ()
{
    int nalu_type;
}
- (void)callBlcok:(CVImageBufferRef)imagRef;

@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDesc;
@property (nonatomic, assign) VTDecompressionSessionRef decompressionSession;

@property (nonatomic, strong) DecodeImgBlock decodeBlock;
@property (nonatomic, strong) DecoderFaile failBlock;

@property (nonatomic, assign) int startCodeIndex;
@property (nonatomic, assign) int secondStartCodeIndex;
@property (nonatomic, assign) int thirdStartCodeIndex;

@property (nonatomic, assign) int blockLength;
@property (nonatomic, assign) int spsSize;
@property (nonatomic, assign) int ppsSize;
@property (nonatomic, assign) int seiSize;

@property (nonatomic, assign) BOOL enterBackground;

@end

@implementation XBHWDecoder

+ (instancetype)sharedDecoder
{
    return [[XBHWDecoder alloc] init];
}

- (void)initDecoder:(DecodeImgBlock)block
{
    _decodeBlock = block;
//    _decompressionSession = NULL;
}

-(void)decoderFaile:(DecoderFaile)block
{
    _failBlock = block;
}

-(void) receivedRawVideoFrame:(uint8_t *)frame withSize:(uint32_t)frameSize
{
    OSStatus status = noErr;
    uint8_t *data = NULL;
    uint8_t *pps = NULL;
    uint8_t *sps = NULL;
    CMSampleBufferRef sampleBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    // I know what my H.264 data source's NALUs look like so I know start code index is always 0.
    // if you don't know where it starts, you can use a for loop similar to how i find the 2nd and 3rd start codes
    _startCodeIndex = 0;
    _secondStartCodeIndex = 0;
    _thirdStartCodeIndex = 0;
    
    _blockLength = 0;
    _spsSize = 0;
    _ppsSize = 0;
    _seiSize = 0;
    //frame的前4位是NALU数据的开始码，也就是00 00 00 01，第5个字节是表示数据类型，转为10进制后，7是sps,8是pps,5是IDR（I帧）信息
    nalu_type = (frame[_startCodeIndex + 4] & 0x1F);
    // if we havent already set up our format description with our SPS PPS parameters, we
    // can't process any frames except type 7 that has our parameters
    
    if (nalu_type != 7 && _formatDesc == NULL)
    {
        return;
    }
    // NALU type 7 is the SPS parameter NALU
    if (nalu_type == 7)
    {
        // find where the second PPS start code begins, (the 0x00 00 00 01 code)
        // from which we also get the length of the first SPS code
        for (int i = _startCodeIndex + 4; i < _startCodeIndex + pframeHeader; i++)
        {
            if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01)
            {
                _secondStartCodeIndex = i;
                _spsSize = _secondStartCodeIndex;   // includes the header in the size
                break;
            }
        }
        // find what the second NALU type is
        nalu_type = (frame[_secondStartCodeIndex + 4] & 0x1F);
     }
    // type 8 is the PPS parameter NALU
    if(nalu_type == 8)
    {
        // find where the NALU after this one starts so we know how long the PPS parameter is
        for (int i = _secondStartCodeIndex + 4; i < _secondStartCodeIndex + pframeHeader; i++)
        {
            if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01)
            {
                _thirdStartCodeIndex = i;
                _ppsSize = _thirdStartCodeIndex - _secondStartCodeIndex;
                break;
            }
        }
        // allocate enough data to fit the SPS and PPS parameters into our data objects.
        // VTD doesn't want you to include the start code header (4 bytes long) so we add the - 4 here
        if ((_spsSize - 4 <= 0) || (_ppsSize - 4 <= 0)) {
            return;
        }
        sps = malloc(_spsSize - 4);
        pps = malloc(_ppsSize - 4);
        
        // copy in the actual sps and pps values, again ignoring the 4 byte header
        memcpy (sps, &frame[4], _spsSize-4);
        memcpy (pps, &frame[_spsSize+4], _ppsSize-4);
        
        // now we set our H264 parameters
        uint8_t*  parameterSetPointers[2] = {sps, pps};
        size_t parameterSetSizes[2] = {_spsSize-4, _ppsSize-4};
        
        CMVideoFormatDescriptionRef formatDescTemp;
        status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, (const uint8_t *const*)parameterSetPointers, parameterSetSizes, 4, &formatDescTemp);
        if(status != noErr){
            _failBlock(YES); // 创建H264文件描述失败,切换到软解码
            return;
        }
        if (!CMFormatDescriptionEqual(formatDescTemp, _formatDesc)){
            _formatDesc = formatDescTemp;
            BOOL ret = [self createDecompSession]; // create VTDecompressionSession.
            if (ret == NO) {
                _formatDesc = NULL;
                return;
            }else{
                // find what the second NALU type is
                nalu_type = (frame[_thirdStartCodeIndex + 4] & 0x1F);
            }
        }else{
            // find what the second NALU type is
            nalu_type = (frame[_thirdStartCodeIndex + 4] & 0x1F);
        }
        if(sps){
            free(sps);
            sps = NULL;
        }
        if (pps){
            free(pps);
            pps = NULL;
        }
    }
    
    // type 6 is an SEI frame NALU.
    if (nalu_type == 6) {
        [self deleteSei:frame withSize:frameSize];
    }
    
    // type 5 is an IDR frame NALU.  The SPS and PPS NALUs should always be followed by an IDR (or IFrame) NALU, as far as I know
    if(nalu_type == 5 )
    {
        // find the offset, or where the SPS and PPS NALUs end and the IDR frame NALU begins
        int offset = _spsSize + _ppsSize + _seiSize;
        _blockLength = frameSize - offset;
        if (_blockLength <= 0) {
            return;
        }
        data = malloc(_blockLength);
        data = memcpy(data, &frame[offset], _blockLength);
    
        // replace the start code header on this NALU with its size.
        // AVCC format requires that you do this.
        // htonl converts the unsigned int from host to network byte order
        uint32_t dataLength32 = htonl (_blockLength - 4);
        memcpy (data, &dataLength32, sizeof (uint32_t));
        
        // create a block buffer from the IDR NALU
        status = CMBlockBufferCreateWithMemoryBlock(NULL, data,  // memoryBlock to hold buffered data
                                                    _blockLength,  // block length of the mem block in bytes.
                                                    kCFAllocatorNull, NULL,
                                                    0, // offsetToData
                                                    _blockLength,   // dataLength of relevant bytes, starting at offsetToData
                                                    0, &blockBuffer);
        
    }
    // NALU type 1 is non-IDR (or PFrame) picture
    if (nalu_type == 1)
    {
        // non-IDR frames do not have an offset due to SPS and PSS, so the approach
        // is similar to the IDR frames just without the offset
        int offset = _seiSize;
        _blockLength = frameSize - offset;
        if (_blockLength <= 0) {
            return;
        }
        data = malloc(_blockLength);
        data = memcpy(data, &frame[offset], _blockLength);
        
        // again, replace the start header with the size of the NALU
        uint32_t dataLength32 = htonl (_blockLength - 4);
        memcpy (data, &dataLength32, sizeof (uint32_t));
        
        status = CMBlockBufferCreateWithMemoryBlock(NULL, data,  // memoryBlock to hold data. If NULL, block will be alloc when needed
                                                    _blockLength,  // overall length of the mem block in bytes
                                                    kCFAllocatorNull, NULL,
                                                    0,     // offsetToData
                                                    _blockLength,  // dataLength of relevant data bytes, starting at offsetToData
                                                    0, &blockBuffer);
    }
    
    if (nalu_type == 1 || nalu_type == 5) {
        // now create our sample buffer from the block buffer,
        if(status == noErr)
        {
            const size_t sampleSize = _blockLength;
            status = CMSampleBufferCreate(kCFAllocatorDefault,
                                          blockBuffer, true, NULL, NULL,
                                          _formatDesc, 1, 0, NULL, 1,
                                          &sampleSize, &sampleBuffer);
        }
        
        if(status == noErr)
        {
            // set some values of the sample buffer's attachments
            CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
            CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
            CFDictionarySetValue(dict, kCMSampleAttachmentKey_DoNotDisplay, kCFBooleanFalse);
            CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
            
            [self render:sampleBuffer];
        }
        
        if (NULL != data)
        {
            free (data);
            data = NULL;
        }
    }
}

- (void)deleteSei:(uint8_t *)frame withSize:(uint32_t)frameSize{
    int offset = 0;
    BOOL loopSEI = NO; // 防止SEI数据帧异常
    for (int i = _thirdStartCodeIndex + 4 + _seiSize; i < frameSize; i++){
        if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01){
            loopSEI = YES;
            offset = i;
            _seiSize = i - _thirdStartCodeIndex;
            break;
        }
    }
    nalu_type = (frame[offset + 4] & 0x1F);
    if (nalu_type == 6 && loopSEI) {
        [self deleteSei:frame withSize:frameSize];
    }else{
        return ;
    }
}

- (void) render:(CMSampleBufferRef)sampleBuffer
{
    CVPixelBufferRef outputPixelBuffer = NULL;
    VTDecodeFrameFlags flags = 0;
    VTDecodeInfoFlags flagOut = 0;
    int status = VTDecompressionSessionDecodeFrame(_decompressionSession, sampleBuffer, flags, &outputPixelBuffer, &flagOut);
    if (status == kVTInvalidSessionErr) {
        _formatDesc = NULL;
    }else  if (status == kVTVideoDecoderMalfunctionErr) {
        NSLog(@"Decode failed status: kVTVideoDecoderMalfunctionErr");
        CVPixelBufferRelease(outputPixelBuffer);
        outputPixelBuffer = NULL;
    }
    else if (status != noErr) {
        _failBlock(YES); // 解码H264失败,切换到软解码
    }
    
    CFRelease(sampleBuffer);
}

//static void VideoDecoderCallback(void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef pixelBuffer, CMTime presentationTimeStamp, CMTime presentationDuration) {
//    XDXDecodeVideoInfo *sourceRef = (XDXDecodeVideoInfo *)sourceFrameRefCon;
//    
//    if (pixelBuffer == NULL) {
//        log4cplus_error(kModuleName, "%s: pixelbuffer is NULL status = %d",__func__,status);
//        if (sourceRef) {
//            free(sourceRef);
//        }
//        return;
//    }
//    
//    XDXVideoDecoder *decoder = (__bridge XDXVideoDecoder *)decompressionOutputRefCon;
//    
//    CMSampleTimingInfo sampleTime = {
//        .presentationTimeStamp  = presentationTimeStamp,
//        .decodeTimeStamp        = presentationTimeStamp
//    };
//    
//    CMSampleBufferRef samplebuffer = [decoder createSampleBufferFromPixelbuffer:pixelBuffer
//                                                                    videoRotate:sourceRef->rotate
//                                                                     timingInfo:sampleTime];
//    
//    if (samplebuffer) {
//        if ([decoder.delegate respondsToSelector:@selector(getVideoDecodeDataCallback:isFirstFrame:)]) {
//            [decoder.delegate getVideoDecodeDataCallback:samplebuffer isFirstFrame:decoder->_isFirstFrame];
//            if (decoder->_isFirstFrame) {
//                decoder->_isFirstFrame = NO;
//            }
//        }
//        CFRelease(samplebuffer);
//    }
//    
//    if (sourceRef) {
//        free(sourceRef);
//    }
//}
-(BOOL) createDecompSession
{
    // make sure to destroy the old VTD session
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = decompressionSessionDecodeFrameCallback;
    
    // this is necessary if you need to make calls to Objective C "self" from within in the callback method.
    callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
    NSDictionary *destinationImageBufferAttributes =[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO],(id)kCVPixelBufferOpenGLESCompatibilityKey,[NSNumber numberWithInt:kCVPixelFormatType_32BGRA],(id)kCVPixelBufferPixelFormatTypeKey,nil];
    
    if (@available(iOS 8.0, *)) {
        OSStatus status =  VTDecompressionSessionCreate(kCFAllocatorDefault, _formatDesc, NULL,
                                                        (__bridge CFDictionaryRef)(destinationImageBufferAttributes), &callBackRecord, &_decompressionSession);
        if(status != noErr){
            _failBlock(YES); //创建解码器失败,切换到软解码
            //kVTInvalidSessionErr -12903
        }else{
            return YES;
        }
    }else{
        _failBlock(YES); //切换到软解码
    }
    return NO;
}

- (void)callBlcok:(CVImageBufferRef)imagRef
{
    CVImageBufferRef buffer = imagRef;
    CVPixelBufferLockBaseAddress(buffer, 0);
    //從 CVImageBufferRef 取得影像的細部資訊
    uint8_t *base = CVPixelBufferGetBaseAddress(buffer);
    size_t width = CVPixelBufferGetWidth(buffer);
    size_t height = CVPixelBufferGetHeight(buffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
    size_t bitsPerComponent =  8;//每个像素点上需要使用的bits位,如果使用32-bit像素和RGB颜色格式，那么RGBA颜色格式中每个组件在屏幕每个像素点上需要使用的bits位就为32/4=8。
    
    //利用取得影像細部資訊格式化 CGContextRef
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  
    CGContextRef cgContext = CGBitmapContextCreate (base, width, height, bitsPerComponent, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    
    CGColorSpaceRelease(colorSpace);
    
    //透過 CGImageRef 將 CGContextRef 轉換成 UIImage
    CGImageRef cgImage = CGBitmapContextCreateImage(cgContext);
    UIImage *image = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    CGContextRelease(cgContext);
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    _decodeBlock(image);
}

- (void) changeToSoftwareDecoder {
    _failBlock(YES); //切换到软解码
}

- (void)deinitVideoDecode{
    if (_decompressionSession) {
        NSLog(@"deinitVideoDecode - _decompressionSession:%@", _decompressionSession);
        VTDecompressionSessionInvalidate(_decompressionSession);
        CFRelease(_decompressionSession);
        _decompressionSession = NULL;
    }
    if (_formatDesc) {
        CFRelease(_formatDesc);
        _formatDesc = NULL;
    }
}

- (void)dealloc{
    [self deinitVideoDecode];
}

@end

void decompressionSessionDecodeFrameCallback(void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef imageBuffer, CMTime presentationTimeStamp, CMTime presentationDuration)
{
    if (status != noErr) {
        NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        __weak XBHWDecoder *pSelf = (__bridge XBHWDecoder *)decompressionOutputRefCon;
        [pSelf changeToSoftwareDecoder];
    }else{
        __weak XBHWDecoder *pSelf = (__bridge XBHWDecoder *)decompressionOutputRefCon;
        [pSelf callBlcok:imageBuffer];
    }
}
