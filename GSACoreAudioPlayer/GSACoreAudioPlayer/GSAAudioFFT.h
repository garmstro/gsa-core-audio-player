//
//  GSAAudioFFT.h
//  GSACoreAudioPlayer
//
//  Created by Geoff Armstrong on 12/4/15.
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


#ifndef GSAAudioFFT_h
#define GSAAudioFFT_h

#import <Accelerate/Accelerate.h>
#import <AVFoundation/AVFoundation.h>

@interface GSAAudioFFT : NSObject

@property (atomic) UInt32 bufferSize;

/**
 Initialize a class instance
 @return The initialized object
 */
- (instancetype) init;

/**
 Initialize a class instance
 @param bufferSize The size of the buffer
 @return The initialized object
 */
- (instancetype) initWithBufferSize: (UInt32) bufferSize;

/**
 Perform a FFT on an audio buffer list
 @param ioData The audio buffer list
 @param bufferSize The number of frames in each buffer
 @returns The power spectrum of the audio data
 */
- (NSArray *)renderFFTWithFrames: (AudioBufferList *) ioData numFrames: (UInt32) bufferSize;

@end

#endif /* GSAAudioFFT_h */
