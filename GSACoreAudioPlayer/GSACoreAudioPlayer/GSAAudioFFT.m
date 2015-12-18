//
//  GSAAudioFFT.m
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


#import <Foundation/Foundation.h>
#import "GSAAudioFFT.h"


#define FFT_MAX_FRAMES 1024

@interface GSAAudioFFT ()

@property (nonatomic) float *windowData;
@property (nonatomic) float *weightedAudioData;
@property (nonatomic) float *frequencyData;
@property (nonatomic) float *maximumData;
@property (nonatomic) DSPSplitComplex A;
@property (nonatomic) FFTSetup fftSetup;
@property (strong, nonatomic) NSMutableArray<NSNumber*> *frequencyArray;

@end

@implementation GSAAudioFFT

- (instancetype)init {
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    [self initializeFFTVariablesWithBufferSize:FFT_MAX_FRAMES];
    
    return self;
}

- (instancetype)initWithBufferSize:(UInt32)bufferSize {
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    _bufferSize = bufferSize;
    
    [self initializeFFTVariablesWithBufferSize:bufferSize];
    
    return self;
}

- (void)initializeFFTVariablesWithBufferSize: (UInt32) bufferSize {
    UInt32 numFrames = bufferSize;
    if (bufferSize > FFT_MAX_FRAMES) {
        numFrames = FFT_MAX_FRAMES;
    }
    UInt32 log2n = log2f(numFrames);
    UInt32 fftN = (1 << log2n);
    UInt32 nOver2 = fftN/2;
    
    _windowData = (float*)malloc(fftN*sizeof(float));
    memset(_windowData, 0, fftN*sizeof(float));
    vDSP_hann_window(_windowData, fftN, vDSP_HANN_NORM);
    
    _weightedAudioData = (float*)malloc(fftN*sizeof(float));
    memset(_weightedAudioData, 0, fftN*sizeof(float));
    
    _frequencyData = (float*)malloc(nOver2*sizeof(float));
    memset(_frequencyData, 0, nOver2*sizeof(float));
    
    _A.realp = (float*)malloc(nOver2 * sizeof(float));
    memset(_A.realp, 0, nOver2*sizeof(float));
    _A.imagp = (float*)malloc(nOver2 * sizeof(float));
    memset(_A.imagp, 0, nOver2*sizeof(float));
    
    _fftSetup = vDSP_create_fftsetup(log2n, FFT_RADIX2);
    _frequencyArray = [[NSMutableArray alloc] initWithCapacity:nOver2];
 }

- (NSArray *)renderFFTWithFrames: (AudioBufferList *) ioData numFrames:(UInt32)bufferSize {
    UInt32 numFrames = bufferSize;
    if (bufferSize > FFT_MAX_FRAMES) {
        numFrames = FFT_MAX_FRAMES;
    }
    UInt32 log2n = log2f(numFrames);
    UInt32 fftN = (1 << log2n);
    UInt32 nOver2 = fftN/2;

    self.bufferSize = fftN;
    vDSP_vmul(ioData->mBuffers[0].mData, 1, self.windowData, 1, self.weightedAudioData, 1, fftN);
    
    //convert real input to even-odd
    vDSP_ctoz((COMPLEX*)self.weightedAudioData, 2, &_A, 1, nOver2);
    //vDSP_ctoz((COMPLEX*)ioData->mBuffers[0].mData, 2, &_A, 1, nOver2);
    
    //fft
    vDSP_fft_zrip(self.fftSetup, &_A, 1, log2n, FFT_FORWARD);
    
    float fftNorm = (float) 1.0 / (2 * numFrames);
    vDSP_vsmul(self.A.realp, 1, &fftNorm, self.A.realp, 1, nOver2);
    vDSP_vsmul(self.A.imagp, 1, &fftNorm, self.A.imagp, 1, nOver2);
    
    //Adjust for zero DC offset (audio)
    self.A.realp[nOver2] = self.A.imagp[0];
    self.A.imagp[nOver2] = 0.0;
    self.A.imagp[0] = 0.0;
    
    //Calculate magnitude
    vDSP_zvmags(&_A, 1, self.frequencyData, 1, nOver2);
    
    //Convert to dB
    //Calculated using reference track
    float zeroRef = 0.15;
    vDSP_vdbcon(self.frequencyData, 1, &zeroRef, self.frequencyData, 1, nOver2, 0);

    for (int i=0; i < nOver2; i++) {
        NSNumber *frequency = [NSNumber numberWithFloat:self.frequencyData[i]];
        [self.frequencyArray setObject:frequency atIndexedSubscript:i];
    }
    return self.frequencyArray;
}

- (void)dealloc {
    free(_windowData);
    free(_weightedAudioData);
    free(_frequencyData);
    free(_A.realp);
    free(_A.imagp);
    vDSP_destroy_fftsetup(_fftSetup);
}

@end