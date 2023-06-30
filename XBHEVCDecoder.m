//
//  XBHEVCDecoder.m
//

/*
 * 重要说明:
 *  1. 此为硬解码类。
 *  2. 手机推荐在iPhone 6s 以上机型。
 *  3. 解码 HEVC 流(文件)仅支持 iOS11 (含)以上系统适用, 低于此系统将自动切换到软件解码, 若无实现软解码则会发生异常!
 */

#import "XBHEVCDecoder.h"
#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVSampleBufferDisplayLayer.h>
#import <AVFoundation/AVVideoSettings.h>

void decompressionSessionDecodeFrameCallbackHEVC(void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef imageBuffer, CMTime presentationTimeStamp, CMTime presentationDuration);

enum NALUnitType {
    NAL_TRAIL_N    = 0,
    NAL_TRAIL_R    = 1, //P
    NAL_TSA_N      = 2,
    NAL_TSA_R      = 3,
    NAL_STSA_N     = 4,
    NAL_STSA_R     = 5,
    NAL_RADL_N     = 6,
    NAL_RADL_R     = 7,
    NAL_RASL_N     = 8,
    NAL_RASL_R     = 9,
    NAL_BLA_W_LP   = 16,
    NAL_BLA_W_RADL = 17,
    NAL_BLA_N_LP   = 18,
    NAL_IDR_W_RADL = 19, //I
    NAL_IDR_N_LP   = 20,
    NAL_CRA_NUT    = 21,
    NAL_VPS        = 32, //VPS
    NAL_SPS        = 33, //SPS
    NAL_PPS        = 34, //PPS
    NAL_AUD        = 35,
    NAL_EOS_NUT    = 36,
    NAL_EOB_NUT    = 37,
    NAL_FD_NUT     = 38,
    NAL_SEI_PREFIX = 39, //SEI
    NAL_SEI_SUFFIX = 40,
};

#define pframeHeader 256

@interface XBHEVCDecoder ()
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
@property (nonatomic, assign) int fourthStartCodeIndex;

@property (nonatomic, assign) int blockLength;
@property (nonatomic, assign) int vpsSize;
@property (nonatomic, assign) int spsSize;
@property (nonatomic, assign) int ppsSize;
@property (nonatomic, assign) int seiSize;

@property (nonatomic, assign) BOOL enterBackground;

@end

@implementation XBHEVCDecoder

+ (instancetype)sharedDecoder
{
    XBHEVCDecoder *sharedInstance = [[XBHEVCDecoder alloc] init];
    return sharedInstance;
}

- (void)initDecoder:(DecodeImgBlock)block
{
    _decodeBlock = block;
//    _decompressionSession = NULL;
}

- (void)decoderFaile:(DecoderFaile)block{
    _failBlock = block;
}

-(void) receivedRawVideoFrame:(uint8_t *)frame withSize:(uint32_t)frameSize
{
    OSStatus status = noErr;
    uint8_t *data = NULL;
    uint8_t *vps = NULL;
    uint8_t *pps = NULL;
    uint8_t *sps = NULL;
    CMSampleBufferRef sampleBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    
    _startCodeIndex = 0;
    _secondStartCodeIndex = 0;
    _thirdStartCodeIndex = 0;
    _fourthStartCodeIndex = 0;

    _blockLength = 0;
    _vpsSize = 0;
    _spsSize = 0;
    _ppsSize = 0;
    _seiSize = 0;

    //The supported NAL unit types to be included in the format description are 32 (video parameter set), 33 (sequence parameter set), 34 (picture parameter set), 39 (prefix SEI) and 40 (suffix SEI). At least one of each parameter set must be provided.
    nalu_type = ((frame[_startCodeIndex + 4] & 0x7E) >> 1);
    if (nalu_type != 32 && _formatDesc == NULL)
    {
        return;
    }
    
    // NALU type 32 is the VPS parameter NALU
    if (nalu_type == 32)
    {
        for (int i = _startCodeIndex + 4; i < _startCodeIndex + pframeHeader; i++)
        {
            if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01)
            {
                _secondStartCodeIndex = i;
                _vpsSize = _secondStartCodeIndex; // includes the header in the size
                break;
            }
        }
        // find what the second NALU type is
        nalu_type = ((frame[_secondStartCodeIndex + 4] & 0x7E) >> 1);
     }
    
    // NALU type 33 is the SPS parameter NALU
    if (nalu_type == 33)
    {
        for (int i = _secondStartCodeIndex + 4; i < _secondStartCodeIndex + pframeHeader; i++)
        {
            if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01)
            {
                _thirdStartCodeIndex = i;
                _spsSize = _thirdStartCodeIndex - _secondStartCodeIndex;
                break;
            }
        }
        // find what the second NALU type is
        nalu_type = ((frame[_thirdStartCodeIndex + 4] & 0x7E) >> 1);
    }
    
    // NALU type 34 is the PPS parameter NALU
    if(nalu_type == 34)
    {
        for (int i = _thirdStartCodeIndex + 4; i < _thirdStartCodeIndex + pframeHeader; i++)
        {
            if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01)
            {
                _fourthStartCodeIndex = i;
                _ppsSize = _fourthStartCodeIndex - _thirdStartCodeIndex;
                break;
            }
        }
        if ((_vpsSize - 4 <= 0) || (_spsSize - 4 <= 0) || (_ppsSize - 4 <= 0)) {
            return;
        }
        vps = malloc(_vpsSize - 4);
        sps = malloc(_spsSize - 4);
        pps = malloc(_ppsSize - 4);
        
        // copy in the actual sps and pps values, again ignoring the 4 byte header
        memcpy (vps, &frame[4], _vpsSize-4);
        memcpy (sps, &frame[_secondStartCodeIndex+4], _spsSize-4);
        memcpy (pps, &frame[_thirdStartCodeIndex+4], _ppsSize-4);
        
        // now we set our H265 parameters
        uint8_t *parameterSetPointers[3] = {vps,sps, pps};
        size_t parameterSetSizes[3] = {_vpsSize-4, _spsSize-4, _ppsSize-4};
        
        CMVideoFormatDescriptionRef formatDescTemp = NULL;
        if (@available(iOS 11.0, *)) {
            status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(kCFAllocatorDefault, 3, (const uint8_t *const*)parameterSetPointers, parameterSetSizes, 4, NULL, &formatDescTemp);
        } else {
            // Fallback on earlier versions
            _failBlock(YES); // 低于iOS 11,切换到软解码
            return;
        }
        if(status != noErr){
            _failBlock(YES); // 创建H265文件描述失败,切换到软解码
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
                nalu_type = ((frame[_fourthStartCodeIndex + 4] & 0x7E) >> 1);
            }
        }else{
            // find what the second NALU type is
            nalu_type = ((frame[_fourthStartCodeIndex + 4] & 0x7E) >> 1);
        }
        if(vps){
            free(vps);
            vps = NULL;
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
    
    // type 39 is an SEI frame NALU.
    if (nalu_type == 39) {
        [self deleteSei:frame withSize:frameSize];
    }
    
    // type 19 is an IDR frame NALU.
    if(nalu_type == 19)
    {
        // find the offset, or where the VPS, SPS and PPS NALUs end and the IDR frame NALU begins
        int offset = _vpsSize + _spsSize + _ppsSize + _seiSize;
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
    
    if (nalu_type == 1 || nalu_type == 19) {
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
    for (int i = _fourthStartCodeIndex + 4 + _seiSize; i < frameSize; i++)
    {
        if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01)
        {
            loopSEI = YES;
            offset = i;
            _seiSize = i - _fourthStartCodeIndex;
            break;
        }
    }
    nalu_type = ((frame[offset + 4] & 0x7E) >> 1);
    if (nalu_type == 39 && loopSEI) {
        [self deleteSei:frame withSize:frameSize];
    }else{
        return ;
    }
}

- (void) render:(CMSampleBufferRef)sampleBuffer
{
    VTDecodeFrameFlags flags = (_synDecoder == YES) ? 0 : kVTDecodeFrame_EnableAsynchronousDecompression;
    VTDecodeInfoFlags flagOut = 0;
    int status = VTDecompressionSessionDecodeFrame(_decompressionSession, sampleBuffer, flags, NULL, &flagOut);
    if (status == kVTInvalidSessionErr) {
        _formatDesc = NULL;
    }else if (status != noErr && !_enterBackground) {
        _failBlock(YES); // 解码H265失败,切换到软解码
    }
    CFRelease(sampleBuffer);
}

- (BOOL)createDecompSession
{
    // make sure to destroy the old VTD session
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = decompressionSessionDecodeFrameCallbackHEVC;
    
    // this is necessary if you need to make calls to Objective C "self" from within in the callback method.
    callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
    NSDictionary *destinationImageBufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO],(id)kCVPixelBufferOpenGLESCompatibilityKey,[NSNumber numberWithInt:kCVPixelFormatType_32BGRA],(id)kCVPixelBufferPixelFormatTypeKey,nil];
    
    if (@available(iOS 11.0, *)) {
        //NSDictionary *videoDecoderSpecification = @{AVVideoCodecKey: AVVideoCodecHEVC};
        OSStatus status =  VTDecompressionSessionCreate(kCFAllocatorDefault,
                                                        _formatDesc,
                                                        NULL,
                                                        (__bridge CFDictionaryRef)(destinationImageBufferAttributes),
                                                        &callBackRecord,
                                                        &_decompressionSession);
        if(status != noErr){
            _failBlock(YES); //创建解码器失败,切换到软解码
            //kVTInvalidSessionErr -12913
        }else{
            return YES;
        }
        
    } else {
        // Fallback on earlier versions
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
    
    //利用取得影像細部資訊格式化 CGContextRef
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef cgContext = CGBitmapContextCreate (base, width, height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    
    CGColorSpaceRelease(colorSpace);
    
    //透過 CGImageRef 將 CGContextRef 轉換成 UIImage
    CGImageRef cgImage = CGBitmapContextCreateImage(cgContext);
    UIImage *image = [UIImage imageWithCGImage:cgImage];
    
    _decodeBlock(image);
    
    CGImageRelease(cgImage);
    CGContextRelease(cgContext);
    CVPixelBufferUnlockBaseAddress(buffer, 0);
}

- (void) changeToSoftwareDecoder {
    _failBlock(YES); //切换到软解码
}

- (void)deinitVideoDecode{
    if (_decompressionSession) {
        VTDecompressionSessionInvalidate(_decompressionSession);
        CFRelease(_decompressionSession);
        _decompressionSession = NULL;
    }
    if (_formatDesc) {
        CFRelease(_formatDesc);
        _formatDesc = NULL;
    }
}

- (void)dealloc
{
    [self deinitVideoDecode];
}

@end

void decompressionSessionDecodeFrameCallbackHEVC(void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef imageBuffer, CMTime presentationTimeStamp, CMTime presentationDuration)
{
    if (status != noErr)
    {
        NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        __weak XBHEVCDecoder *pSelf = (__bridge XBHEVCDecoder *)decompressionOutputRefCon;
        [pSelf changeToSoftwareDecoder];
    }else{
        @try {
            __weak XBHEVCDecoder *pSelf = (__bridge XBHEVCDecoder *)decompressionOutputRefCon;
            [pSelf callBlcok:imageBuffer];
        } @catch (NSException *exception) {
            NSLog(@"... exception:%@", exception);
        } @finally {
            
        }
    }
}
