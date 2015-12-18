//
//  GSACoreAudioPlayer.m
//  GSACoreAudioPlayer
//
//  Created by Geoff Armstrong on 11/29/15.
//  Copyright © 2015 Geoff Armstrong. All rights reserved.
//  email: garmstro@gmail.com
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//


#import <Foundation/Foundation.h>
#import "GSACoreAudioPlayer.h"

#define EXPORT_NAME @"exported.caf"

/**
 GSACoreAudioPlayer extension containing private/public class variables
 */
@interface GSACoreAudioPlayer ()
#pragma mark - Private Class Variables

@property (nonatomic) BOOL streaming;
@property (nonatomic) AUGraph graph;

@property (nonatomic) AUNode inputNode;
@property (nonatomic) AUNode outputNode;

@property (nonatomic) AudioUnit inputUnit;
@property (nonatomic) AudioUnit outputUnit;

@property (nonatomic) AudioFileID audioFile;
@property (nonatomic) ExtAudioFileRef extAudioFile;

@property (nonatomic) ScheduledAudioFileRegion region;
@property (nonatomic) AudioStreamBasicDescription clientFormat;

@property (nonatomic) bool started;
@property (nonatomic) bool filePlaying;

@property (nonatomic) SInt64 frameIndex;
@property (nonatomic) Float64 startTime;
@property (nonatomic) Float64 elapsedTime;

//Re-assign these properties to readwrite
@property (nonatomic, readwrite) NSTimeInterval duration;
@property (nonatomic, readwrite) NSTimeInterval currentTime;
@property (nonatomic, readwrite) bool playing;

@end

/**
 GSACoreAudioPlayer is an audio player that levereges the core audio framework
 */
@implementation GSACoreAudioPlayer

#pragma mark - Class Methods

/**
 Initialize a player instance
 @return The initialized player
 */
- (instancetype) init {
    //Default is to stream the file
    return [self initWithStreaming:YES];
}

/**
 Initialize a player instance
 @return The initialized player
 */
- (instancetype) initWithStreaming: (BOOL)streaming {
    self = [super init];
    
    if (self) {
        //Initialize instance variables
        _delegate = nil;
        
        _started = false;
        _filePlaying = false;
        _playing = false;
        
        _duration = 0.f;
        _currentTime = 0.f;
        _startTime = -1;
        _elapsedTime = 0.f;
        
        _streaming = streaming;
        
        [self initializeAudioGraph];
    }
    
    return self;
}

/**
 Play the audio file located at the asset URL
 @return The initialized player
 */
- (void)playAudioFileWithAssetURL: (NSURL *)assetURL {
    if (self.streaming) {
        [self streamAudioFileWithAssetURL:assetURL];
    }
    else {
        [self openAudioFileWithAssetURL:assetURL];
    }
}

#pragma mark - Start/Stop
/**
 Starts or Stops the playback from the audio player
 */
- (void) togglePlayback {
    if (self.playing) {
        CheckError(AudioOutputUnitStop(self.outputUnit), "Audio Output Unit Failed To Stop");
    } else {
        CheckError(AudioOutputUnitStart(self.outputUnit), "Audio Output Unit Failed To Start");
    }
    self.playing = !self.playing;
    //If file is not being streamed, update the region/timestamp
    if (!self.streaming && self.started) {
        AudioUnitReset(self.inputUnit, kAudioUnitScope_Global, 0);
        AudioUnitSetProperty(self.inputUnit, kAudioUnitProperty_ScheduledFileRegion, kAudioUnitScope_Global, 0, &_region, sizeof(self.region));
        
        AudioTimeStamp regionStartTime;
        memset(&regionStartTime, 0, sizeof(regionStartTime));
        regionStartTime.mFlags = kAudioTimeStampSampleTimeValid;
        regionStartTime.mSampleTime = -1;
        AudioUnitSetProperty(self.inputUnit, kAudioUnitProperty_ScheduleStartTimeStamp, kAudioUnitScope_Global, 0, &regionStartTime, sizeof(regionStartTime));
    };
}

/**
 Starts the playback from the audio player
 */
- (void) play {
    if (!self.playing) {
        [self togglePlayback];
    }
}

/**
 Stops the playback from the audio player
 */
- (void) stop {
    CheckError(AudioOutputUnitStop(self.outputUnit), "Audio Output Unit Failed To Stop");
    self.started = false;
    self.playing = false;
    self.frameIndex = 0;
    self.startTime = -1;
    self.elapsedTime = 0.f;
}

/**
 Starts or Stops the playback from the audio player
 */
- (void) pause {
    if (self.playing) {
        self.elapsedTime = self.currentTime;
        self.startTime = -1;
        [self togglePlayback];
    }
}

/**
 Start playback and notify the delegate that playback is ready
 @param audioPlayer The audio player that is ready for playback
 */
- (void) startPlayback {
    //Tell the delegate that playback is ready (i.e. to stop activity indicator)
    //Audio Player may be on dispatch queue
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.delegate) {
            if ([self.delegate respondsToSelector:@selector(audioPlayerPlaybackReady:)]) {
                [self.delegate audioPlayerPlaybackReady: self];
            }
        }
    });
    
    [self togglePlayback];
}

/**
 Stop playback and notify the delegate that playback is ready
 @param audioPlayer The audio player that is ready for playback
 */
- (void) stopPlayback {
    //Tell the delegate that playback is ready (i.e. to stop activity indicator)
    //Audio Player may be on dispatch queue
    [self stop];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.delegate) {
            if ([self.delegate respondsToSelector:@selector(audioPlayerDidFinishPlaying:successfully:)]) {
                [self.delegate audioPlayerDidFinishPlaying:self successfully:YES];
            }
        }
    });
}

#pragma mark - Initialization
/**
 Initialize the audio graph and audio units
 */
- (void)initializeAudioGraph {
    //Create the Audio Unit Graph
    CheckError(NewAUGraph(&_graph), "New AU Graph");
    
    AudioComponentDescription inputDesc;
    if (_streaming) {
        //Setup Input Node for File Stream
        inputDesc.componentType = kAudioUnitType_FormatConverter;
        inputDesc.componentSubType = kAudioUnitSubType_AUConverter;
        inputDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
        inputDesc.componentFlags = 0;
        inputDesc.componentFlagsMask = 0;
    }
    else {
        //Setup Input Node for File Read
        inputDesc.componentType = kAudioUnitType_Generator;
        inputDesc.componentSubType = kAudioUnitSubType_AudioFilePlayer;
        inputDesc.componentFlags = 0;
        inputDesc.componentFlagsMask = 0;
        inputDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    }
    
    AudioComponentDescription outputDesc;
    outputDesc.componentType = kAudioUnitType_Output;
    outputDesc.componentSubType = kAudioUnitSubType_RemoteIO;
    outputDesc.componentFlags = 0;
    outputDesc.componentFlagsMask = 0;
    outputDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    //Initialize the Audio Nodes
    CheckError(AUGraphAddNode(_graph, &inputDesc, &_inputNode), "Add File Player Node");
    CheckError(AUGraphAddNode(_graph, &outputDesc, &_outputNode), "Add Output Node");
    
    //Open the audio graph
    CheckError(AUGraphOpen(_graph), "Open Audio Graph");
    
    //Initialize the Audio Units
    CheckError(AUGraphNodeInfo(_graph, _inputNode, NULL, &_inputUnit), "Add File Player Node Info");
    CheckError(AUGraphNodeInfo(_graph, _outputNode, NULL, &_outputUnit), "Add File Player Node Info");
    
    if (_streaming) {
        // describe the input audio format... here we're using LPCM 32 bit floating point samples
        AudioStreamBasicDescription inputFormat;
        inputFormat.mFormatID = kAudioFormatLinearPCM;
        inputFormat.mFormatFlags       = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsPacked | kAudioFormatFlagIsFloat;
        inputFormat.mSampleRate        = 44100;
        inputFormat.mChannelsPerFrame  = 2;
        inputFormat.mBitsPerChannel    = 32;
        inputFormat.mBytesPerPacket    = (inputFormat.mBitsPerChannel / 8) * inputFormat.mChannelsPerFrame;
        inputFormat.mFramesPerPacket   = 1;
        inputFormat.mBytesPerFrame     = inputFormat.mBytesPerPacket;
        // set the audio format on the input scope (kAudioUnitScope_Input) of the output bus (0) of the input unit
        CheckError(AudioUnitSetProperty(_inputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &inputFormat, sizeof(inputFormat)),"AudioUnitSetProperty StreamFormat");
        // set up a render callback struct consisting of our output render callback (above) and a reference to self
        AURenderCallbackStruct callbackStruct;
        callbackStruct.inputProc = InputRenderCallback;
        callbackStruct.inputProcRefCon = (__bridge void*)self;
        // add the callback struct to the input unit (again, that's to the input scope of the output bus)
        CheckError(AudioUnitSetProperty(_inputUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callbackStruct, sizeof(callbackStruct)),"AudioUnitSetProperty SetRenderCallback");
    }
    
    //Add the output render callback
    CheckError(AudioUnitAddRenderNotify(_outputUnit, OutputAudioUnitRenderNotify, (__bridge void *) self), "Add Output Audio Render");
    
    //Connect the Audio Units
    CheckError(AUGraphConnectNodeInput(_graph, _inputNode, 0, _outputNode, 0), "Connect File Player Node");
    
    //Update and Initialize the Graph
    CheckError(AUGraphUpdate(_graph, NULL), "Update Graph");
    CheckError(AUGraphInitialize(_graph), "Initialize Graph");
}

#pragma mark - File Reading
/**
 Opens an audio asset at the url and prepares it to be streamed to audio output
 Modified from https://github.com/abeldomingues/Stream-Ipod-Audio-From-Disk
 @param assetURL The asset URL for the audio file
 */
- (void)streamAudioFileWithAssetURL:(NSURL*)assetURL {
    
    if(!self.streaming) {
        NSLog(@"Player must be initialized with isStreaming = YES");
        return;
    }
    
    // get a reference to the selected file and open it for reading by first (a) NULLing out our existing ExtAudioFileRef...
    self.extAudioFile = NULL;
    // then (b) casting the track's NSURL to a CFURLRef ('cause that's what ExtAudioFileOpenURL requires)...
    CFURLRef cfurl = (__bridge CFURLRef)assetURL;
    // and finally (c) opening the file for reading.
    CheckError(ExtAudioFileOpenURL(cfurl, &_extAudioFile),
               "ExtAudioFileOpenURL Failed");
    
    // get the total number of sample frames in the file (we're not actually doing anything with  totalFrames in this demo, but you'll nearly always want to grab the file's length as soon as you open it for reading)
    SInt64 totalFrames;
    UInt32 dataSize = sizeof(totalFrames);
    CheckError(ExtAudioFileGetProperty(self.extAudioFile, kExtAudioFileProperty_FileLengthFrames, &dataSize, &totalFrames),
               "ExtAudioFileGetProperty FileLengthFrames failed");
    
    // get the file's native format (so ExtAudioFileRead knows what format it's converting _from_)
    AudioStreamBasicDescription asbd;
    dataSize = sizeof(asbd);
    CheckError(ExtAudioFileGetProperty(self.extAudioFile, kExtAudioFileProperty_FileDataFormat, &dataSize, &asbd), "ExtAudioFileGetProperty FileDataFormat failed");
    
    //Estimate the duration of the file
    if (asbd.mSampleRate != 0) {
        self.duration = (totalFrames/asbd.mSampleRate);
    }
    
    // set up a client format (so ExtAudioFileRead knows what format it's converting _to_ - here we're converting to LPCM 32-bit floating point, which is what we've told the output audio unit to expect!)
    AudioStreamBasicDescription clientFormat;
    clientFormat.mFormatID = kAudioFormatLinearPCM;
    clientFormat.mFormatFlags       = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsPacked | kAudioFormatFlagIsFloat;
    clientFormat.mSampleRate        = 44100;
    clientFormat.mChannelsPerFrame  = 2;
    clientFormat.mBitsPerChannel    = 32;
    clientFormat.mBytesPerPacket    = (clientFormat.mBitsPerChannel / 8) * clientFormat.mChannelsPerFrame;
    clientFormat.mFramesPerPacket   = 1;
    clientFormat.mBytesPerFrame     = clientFormat.mBytesPerPacket;
    
    // set the client format on our ExtAudioFileRef
    CheckError(ExtAudioFileSetProperty(self.extAudioFile, kExtAudioFileProperty_ClientDataFormat, sizeof(clientFormat), &clientFormat), "ExtAudioFileSetProperty ClientDataFormat failed");
    _clientFormat = clientFormat;
    
    // finally, set our _frameIndex property to 0 in prep for the first read
    self.frameIndex = 0;
    self.startTime = -1;
    self.elapsedTime = 0.f;
    
    [self startPlayback];
}

/**
 Setup a player with an audio file asset by copying the asset to the application bundle
 Modified from VTM_AViPodReader
 @param assetURL The asset URL for the audio file
 */
-(void) openAudioFileWithAssetURL: (NSURL *) assetURL {
    
    if(self.streaming) {
        NSLog(@"Player must be initialized with isStreaming = NO");
        return;
    }
    
    //Copy the asset to a file in the application Documents directory
    //First read the asset
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:assetURL options:nil];
    NSError *assetError = nil;
    AVAssetReader *assetReader = [AVAssetReader assetReaderWithAsset:asset error:&assetError];
    if (assetError) {
        NSLog (@"Error: %@", assetError);
        return;
    }
    
    //Set the output of the asset reader
    AVAssetReaderOutput *assetReaderOutput = [AVAssetReaderAudioMixOutput
                                              assetReaderAudioMixOutputWithAudioTracks:asset.tracks
                                              audioSettings: nil];
    if (! [assetReader canAddOutput: assetReaderOutput]) {
        NSLog (@"Can't add reader output");
        return;
    }
    [assetReader addOutput: assetReaderOutput];
    
    //Setup the file path for the exported file
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectoryPath = [dirs objectAtIndex:0];
    NSString *exportPath = [documentsDirectoryPath stringByAppendingPathComponent:EXPORT_NAME];
    if ([[NSFileManager defaultManager] fileExistsAtPath:exportPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:exportPath error:nil];
    }
    NSURL *exportURL = [NSURL fileURLWithPath:exportPath];
    AVAssetWriter *assetWriter = [AVAssetWriter assetWriterWithURL:exportURL
                                                          fileType:AVFileTypeCoreAudioFormat
                                                             error:&assetError];
    if (assetError) {
        NSLog (@"Error: %@", assetError);
        return;
    }
    
    //Prepare the format for the output file
    AudioChannelLayout channelLayout;
    memset(&channelLayout, 0, sizeof(AudioChannelLayout));
    channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
    NSDictionary *outputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithInt:kAudioFormatLinearPCM], AVFormatIDKey,
                                    [NSNumber numberWithFloat:44100.0], AVSampleRateKey,
                                    [NSNumber numberWithInt:2], AVNumberOfChannelsKey,
                                    [NSData dataWithBytes:&channelLayout length:sizeof(AudioChannelLayout)], AVChannelLayoutKey,
                                    [NSNumber numberWithInt:16], AVLinearPCMBitDepthKey,
                                    [NSNumber numberWithBool:NO], AVLinearPCMIsNonInterleaved,
                                    [NSNumber numberWithBool:NO], AVLinearPCMIsFloatKey,
                                    [NSNumber numberWithBool:NO], AVLinearPCMIsBigEndianKey,
                                    nil];
    AVAssetWriterInput *assetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                                                              outputSettings:outputSettings];
    
    //Setup input to the asset writer
    if ([assetWriter canAddInput:assetWriterInput]) {
        [assetWriter addInput:assetWriterInput];
    } else {
        NSLog (@"Can't add asset writer input");
        return;
    }
    
    //We are not dealing with realtime audio, but recorded audio
    assetWriterInput.expectsMediaDataInRealTime = NO;
    
    //Start reading/writing the asset
    [assetWriter startWriting];
    [assetReader startReading];
    
    AVAssetTrack *soundTrack = [asset.tracks objectAtIndex:0];
    CMTime fileStartTime = CMTimeMake (0, soundTrack.naturalTimeScale);
    [assetWriter startSessionAtSourceTime: fileStartTime];
    
    //Block variable so that it can be updated within the block
    __block UInt64 convertedByteCount = 0;
    
    dispatch_queue_t mediaInputQueue = dispatch_queue_create("mediaInputQueue", NULL);
    [assetWriterInput requestMediaDataWhenReadyOnQueue:mediaInputQueue
                                            usingBlock: ^
     {
         while (assetWriterInput.readyForMoreMediaData) {
             CMSampleBufferRef nextBuffer = [assetReaderOutput copyNextSampleBuffer];
             if (nextBuffer) {
                 //If next buffer exists, append buffer
                 [assetWriterInput appendSampleBuffer: nextBuffer];
                 //NSLog (@"appended a buffer (%zu bytes)", CMSampleBufferGetTotalSampleSize (nextBuffer));
                 convertedByteCount += CMSampleBufferGetTotalSampleSize(nextBuffer);
             } else {
                 //Done writing
                 [assetWriterInput markAsFinished];
                 
                 //Finish Writing the file and call the completion selector
                 [assetWriter finishWritingWithCompletionHandler:^{
                     //Do this on the main thread, not in the mediaInputQueue
                     dispatch_async(dispatch_get_main_queue(), ^{
                         [self playAudioFileWithBundleURL:exportURL];
                     });
                 }];
                 [assetReader cancelReading];
//                 NSDictionary *outputFileAttributes = [[NSFileManager defaultManager]
//                                                       attributesOfItemAtPath:exportPath
//                                                       error:nil];
//                 NSLog (@"Done Writing. File size is %llu", [outputFileAttributes fileSize]);
                 break;
             }
         } //End of assetWriter block
     }];
}

/**
 Setup a player with an audio file url from the application bundle
 @param fileURL NSURL for the file from the application bundle
 */
- (void) playAudioFileWithBundleURL: (NSURL *) fileURL {
    if(self.streaming) {
        NSLog(@"Player must be initialized with isStreaming = NO");
        return;
    }
    
    self.audioFile = NULL;

    CheckError(AudioFileOpenURL((__bridge CFURLRef) fileURL, kAudioFileReadPermission, 0, &_audioFile), "AudioFileOpenURL");
    
    AudioStreamBasicDescription fileFormat;
    UInt64 numPackets;
    UInt32 size = sizeof(AudioStreamBasicDescription);
    CheckError(AudioFileGetProperty(self.audioFile, kAudioFilePropertyDataFormat, &size, &fileFormat), "File Data Format");
    
    size = sizeof(numPackets);
    CheckError(AudioFileGetProperty(self.audioFile, kAudioFilePropertyAudioDataPacketCount, &size, &numPackets), "File Packet Count");
    
    Float64 duration;
    size = sizeof(duration);
    CheckError(AudioFileGetProperty(self.audioFile, kAudioFilePropertyEstimatedDuration, &size, &duration), "File Estimated Duration");
    
    self.duration = (NSTimeInterval) duration;
    
    ScheduledAudioFileRegion region;
    memset(&region.mTimeStamp, 0, sizeof(region.mTimeStamp));
    //Set time stamp to the beginning of the file
    region.mTimeStamp.mFlags = kAudioTimeStampSampleTimeValid;
    region.mTimeStamp.mSampleTime = 0;
    //Setup completion handler
    region.mCompletionProc = AudioFileCompletionCallback;
    region.mCompletionProcUserData = (__bridge void*)self;
    //Set the audio file ID
    region.mAudioFile = self.audioFile;
    //Don't loop playback
    region.mLoopCount = 0;
    //Start at the beginning
    region.mStartFrame = 0;
    //Play the full file
    region.mFramesToPlay = (UInt32) (numPackets * fileFormat.mFramesPerPacket);
    //Set the property to the variable (this cleans things up a bit)
    _region = region;
    
    CheckError(AudioUnitSetProperty(self.inputUnit, kAudioUnitProperty_ScheduledFileIDs, kAudioUnitScope_Global, 0, &_audioFile, sizeof(self.audioFile)), "Schedule File");
    
    CheckError(AudioUnitSetProperty(self.inputUnit, kAudioUnitProperty_ScheduledFileRegion, kAudioUnitScope_Global, 0, &_region, sizeof(self.region)), "File Region");
    
    UInt32 defaultValue = 0;
    CheckError(AudioUnitSetProperty(self.inputUnit, kAudioUnitProperty_ScheduledFilePrime, kAudioUnitScope_Global, 0, &defaultValue, sizeof(defaultValue)), "File Prime");
    
    AudioTimeStamp schedStartTime;
    memset(&schedStartTime, 0, sizeof(schedStartTime));
    schedStartTime.mFlags = kAudioTimeStampSampleTimeValid;
    schedStartTime.mSampleTime = -1;
    CheckError(AudioUnitSetProperty(self.inputUnit, kAudioUnitProperty_ScheduleStartTimeStamp, kAudioUnitScope_Global, 0, &schedStartTime, sizeof(schedStartTime)), "Start File");
    
    self.startTime = -1;
    self.elapsedTime = 0.f;
    self.started = true;
    
    [self startPlayback];

}

#pragma mark - Render Callback Helper Functions
/**
 Reads Frames from an audioBufferList and updates the current frame
 @param frames The number of available frames
 @param audioBufferList The Audio Buffer List from the render callback (ioData)
 @param bufferSize The size of the Audio Buffer returned to the audio unit
 */
- (void)readFrames:(UInt32)frames audioBufferList:(AudioBufferList *)audioBufferList bufferSize:(UInt32 *)bufferSize {
    if (self.extAudioFile) {
        SInt64 totalFrames;
        UInt32 dataSize = sizeof(totalFrames);
        CheckError(ExtAudioFileGetProperty(self.extAudioFile, kExtAudioFileProperty_FileLengthFrames, &dataSize, &totalFrames),
                   "ExtAudioFileGetProperty FileLengthFrames failed");
        
        // seek to the current frame index
        CheckError(ExtAudioFileSeek(self.extAudioFile, self.frameIndex), nil);
        // do the read
        CheckError(ExtAudioFileRead(self.extAudioFile, &frames, audioBufferList),
                   "Failed to read audio data from audio file");
        *bufferSize = audioBufferList->mBuffers[0].mDataByteSize/sizeof(float);
        // update the frame index so we know where to pick up when the next request for samples comes in from the render callback
        self.frameIndex += frames;
        
        //EOF
        if (frames == 0) {
            [self stopPlayback];
        }
    }
}

#pragma mark - C Helper functions
/**
 Kevin Avila/Chris Adamson's CheckError function for OSStatus functions in core audio
 "Learning Core Audio: A Hands-on Guide to Audio Programming for Mac and IOS"
 @param error The function that returns the OSStatus error
 @param operation A description of the function that caused the error
 */
static void CheckError(OSStatus error, const char *operation)
{
    if (error == noErr) return;
    
    fprintf(stderr, "Error: %s (%d)\n", operation, (int)error);
    
    exit(1);
}

/**
 Completion Proc for Audio File Player
 @param userData Custom data that you provided when registering your callback with the audio unit.
 @param fileRegion The file region for the scheduled audio file
 @param result Result code for why the player stopped
  */
static void AudioFileCompletionCallback(void * __nullable userData, ScheduledAudioFileRegion *fileRegion, OSStatus result)
{
    GSACoreAudioPlayer *self = (__bridge GSACoreAudioPlayer*)userData;
    if (self.filePlaying) {
        [self stopPlayback];
        self.filePlaying = false;
    }
    else {
        self.filePlaying = true;
    }
}

/**
 Callback function for the input audio unit rendering.
 @param inRefCon Custom data that you provided when registering your callback with the audio unit.
 @param ioActionFlags Flags used to describe more about the context of this call (pre or post in the notify case for instance).
 @param inTimeStamp The timestamp associated with this call of audio unit render.
 @param inBusNumber The bus number associated with this call of audio unit render.
 @param inNumberFrames The number of sample frames that will be represented in the audio data in the provided ioData parameter
 @param ioData The AudioBufferList that will be used to contain the rendered or provided audio data.
 */
static OSStatus InputRenderCallback (void *inRefCon,
                                     AudioUnitRenderActionFlags	* ioActionFlags,
                                     const AudioTimeStamp * inTimeStamp,
                                     UInt32 inOutputBusNumber,
                                     UInt32 inNumberFrames,
                                     AudioBufferList * ioData)
{
    GSACoreAudioPlayer *self = (__bridge GSACoreAudioPlayer*)inRefCon;
    @autoreleasepool
    {
        UInt32 bufferSize;
        [self readFrames:inNumberFrames
         audioBufferList:ioData
              bufferSize:&bufferSize];
    }
    return noErr;
}

/**
 Callback function for the output audio unit rendering.
 @param inRefCon Custom data that you provided when registering your callback with the audio unit.
 @param ioActionFlags Flags used to describe more about the context of this call (pre or post in the notify case for instance).
 @param inTimeStamp The timestamp associated with this call of audio unit render.
 @param inBusNumber The bus number associated with this call of audio unit render.
 @param inNumberFrames The number of sample frames that will be represented in the audio data in the provided ioData parameter
 @param ioData The AudioBufferList that will be used to contain the rendered or provided audio data.
 */
static OSStatus OutputAudioUnitRenderNotify(void *inRefCon,
                                            AudioUnitRenderActionFlags *ioActionFlags,
                                            const AudioTimeStamp *inTimeStamp,
                                            UInt32 inBusNumber,
                                            UInt32 inNumberFrames,
                                            AudioBufferList *ioData)
{
    GSACoreAudioPlayer *self = (__bridge GSACoreAudioPlayer*)inRefCon;
    @autoreleasepool
    {
        if (*ioActionFlags & kAudioUnitRenderAction_PostRender) {
            if (self.startTime == -1) {
                self.startTime = inTimeStamp->mSampleTime;
            }
            //Update current time
            self.currentTime = self.elapsedTime + ((inTimeStamp->mSampleTime - self.startTime) / 44100.0f);

            if (self.delegate) {
                if ([self.delegate respondsToSelector:@selector(audioPlayer:didSendAudioBuffers:withFrames:atTimeStamp:)]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.delegate audioPlayer:self
                               didSendAudioBuffers:ioData
                                        withFrames:inNumberFrames
                                       atTimeStamp:inTimeStamp];
                    });
                }
            }
        }
    }

    return noErr;
}


@end
