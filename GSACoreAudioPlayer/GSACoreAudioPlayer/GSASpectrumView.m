//
//  GSASpectrumView.m
//  GSACoreAudioPlayer
//
//  Created by Geoff Armstrong on 12/11/15.
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


#import "GSASpectrumView.h"

#define MIN_DB_VAL -96.f
#define MAX_DB_VAL 0.f

@interface GSASpectrumView ()

@property (strong, nonatomic) NSNumber *spectrumMin;

@end

@implementation GSASpectrumView

- (id) initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) {
        return nil;
    }
    
    [self initializeSpectrumView];
    
    return self;
}

- (id) initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    
    if (!self) {
        return nil;
    }
    
    [self initializeSpectrumView];
    
    return self;
}

- (void) initializeSpectrumView {
    self.backgroundColor = [UIColor clearColor];
    _spectrumColor = [UIColor blackColor];
    [self setNumBins:256];
    
    //Set default minimum to fixed value
    [self setFixedMinimum:YES];
    
}

- (void) setFixedMinimum:(BOOL)fixedMinimum {
    if (fixedMinimum == YES) {
        _spectrumMin = [NSNumber numberWithFloat:MIN_DB_VAL];
    }
    else {
        _spectrumMin = [NSNumber numberWithFloat:MAX_DB_VAL];
    }
    _fixedMinimum = fixedMinimum;
}

- (void) drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(context, self.spectrumColor.CGColor);
    
    if (!self.fixedMinimum) {
        //Find min of spectrum array
        __block NSNumber *magMin = [NSNumber numberWithFloat:0.0];
        [self.spectrumData enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSNumber *magValue = obj;
            if (![magValue isEqual:[NSDecimalNumber notANumber]] &&
                ![magValue isEqual:[NSNumber numberWithFloat:-INFINITY]]) {
                if ([magValue compare: magMin] == NSOrderedAscending) {
                    magMin = magValue;
                }
            }
        }];
        
        //Reset the running counter to the minimum value if necessary
        if ([self.spectrumMin compare:magMin] == NSOrderedDescending) {
            self.spectrumMin = magMin;
        }
    }
    
    if (self.spectrumData) {
        if (self.spectrumData.count > 0) {
            
            //Calculate the number of FFT bins to average
            if (self.numBins > self.spectrumData.count) {
                self.numBins = self.spectrumData.count;
            }
            UInt16 binSize = self.spectrumData.count / self.numBins;
            
            //Plot the spectral points for each bin
            for (int i=0; i < self.numBins; i++) {
                //Calculate the xOffset of the spectrum bin
                CGFloat xWidth = rect.size.width / self.numBins;
                CGFloat xOffset = (i * xWidth) + xWidth / 2.0;
                
                //Calculate the yOffset for the magnitude, averaging over the bin size
                CGFloat yOffset = 0.0;
                for (int j=0; j < binSize; j++) {
                    if (![self.spectrumData[i + j] isEqual:[NSDecimalNumber notANumber]]) {
                        yOffset += [self.spectrumData[i + j] floatValue];
                    }
                }
                yOffset /= binSize;
                
                //Plot the spectrum point in the view
                CGFloat scale = rect.size.height / [self.spectrumMin floatValue];
                CGRect pointRect = CGRectMake(xOffset, scale*yOffset, 2, 2);
                CGContextFillRect(context, pointRect);
            }
        }
    }
}

- (void) touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.fixedMinimum = !self.fixedMinimum;
}

@end
