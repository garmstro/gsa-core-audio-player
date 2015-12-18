//
//  GSACoreAudioPlayer.h
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


#ifndef GSACoreAudioPlayer_h
#define GSACoreAudioPlayer_h

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

@protocol GSACoreAudioPlayerDelegate;

/**
 GSACoreAudioPlayer is an audio player that levereges the core audio framework
 */
@interface GSACoreAudioPlayer : NSObject

#pragma mark - Class Variables
/**
 @name GSACoreAudioPlayer class variables
 */

@property (nonatomic, weak) id<GSACoreAudioPlayerDelegate> delegate;
@property (nonatomic, readonly) bool playing;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) NSTimeInterval currentTime;

#pragma mark - Class Methods

/**
 Initialize a player instance
 Default isStreaming = YES
 @return The initialized player
 */
- (instancetype) init;

/**
 Initialize a player instance
 @return The initialized player
 */
- (instancetype) initWithStreaming: (BOOL) streaming;

/**
 Play the audio file located at the asset URL
 @param assetURL The asset URL for the audio file
 */
- (void)playAudioFileWithAssetURL: (NSURL *)assetURL;

/**
 Setup a player with an audio file url from the application bundle
 @param fileURL NSURL for the file from the application bundle
 */
- (void)playAudioFileWithBundleURL: (NSURL *)fileURL;

/**
 Starts or stops playback depending on the state of the player
 */
- (void) togglePlayback;

/**
 Starts playback 
 */
- (void) play;

/**
 Stops playback
 */
- (void) stop;

/**
 Pauses Playback
 */
- (void) pause;

@end

@protocol GSACoreAudioPlayerDelegate <NSObject>

/**
 Delegate function called when playback finishes
 @param audioPlayer The audio player that is ready for playback
 @param successfully YES if the player finished playing the file, NO if it did not
 */
- (void) audioPlayerDidFinishPlaying: (GSACoreAudioPlayer *) audioPlayer successfully:(BOOL)flag;

@optional
/**
 Delegate function called when playback is ready
 @param audioPlayer The audio player that is ready for playback
 */
- (void) audioPlayerPlaybackReady: (GSACoreAudioPlayer *) audioPlayer;

/**
 Delegate function called for processing audio data before it is sent to output device
 @param audioPlayer The audio player that is returning data
 @param didSendAudioBuffers The AudioBufferList to be sent to the output device
 */
- (void)audioPlayer: (GSACoreAudioPlayer *) audioPlayer didSendAudioBuffers: (AudioBufferList *) audioBufferList withFrames: (UInt32) numFrames atTimeStamp: (const AudioTimeStamp *) timeStamp;

@end

#endif /* GSACoreAudioPlayer_h */
