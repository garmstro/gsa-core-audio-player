//
//  ViewController.m
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


#import "ViewController.h"
#import <MediaPlayer/MediaPlayer.h>
#import <Accelerate/Accelerate.h>
#import "GSACoreAudioPlayer.h"
#import "GSAAudioFFT.h"
#import "GSASpectrumView.h"

@interface ViewController () <MPMediaPickerControllerDelegate, GSACoreAudioPlayerDelegate>

@property (strong, nonatomic) MPMediaPickerController *picker;
@property (strong, nonatomic) GSACoreAudioPlayer *player;
@property (strong, nonatomic) GSAAudioFFT *fftRender;

@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *mediaPickerActivityIndicator;
@property (weak, nonatomic) IBOutlet GSASpectrumView *audioSpectrumView;
@property (weak, nonatomic) IBOutlet UIButton *playStopButton;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.playStopButton.enabled = NO;
    
    [self startActivityIndicator];
    [self setupMediaPicker];
    [self setupAudioPlayer];
    [self setupAudioRender];
    [self setupSpectrumView];
    
    [self startMediaPicker];
    
    //Test player with reference mp3
    //NSURL *testURL = [[NSBundle mainBundle] URLForResource:@"track57" withExtension:@"mp3"];
    //NSURL *testURL = [[NSBundle mainBundle] URLForResource:@"track54" withExtension:@"mp3"];
    //[self.player playAudioFileWithBundleURL:testURL];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)setupMediaPicker {
    self.picker = [MPMediaPickerController new];
    self.picker.delegate = self;
    self.picker.showsCloudItems = NO;
    //For now just a single item
    self.picker.allowsPickingMultipleItems = NO;
}

- (void)setupAudioPlayer {
    self.player = [[GSACoreAudioPlayer alloc] initWithStreaming:YES];
    self.player.delegate = self;
}

- (void)setupAudioRender {
    self.fftRender = [[GSAAudioFFT alloc] init];
}

- (void) startMediaPicker {
    [self presentViewController:self.picker animated:YES completion:^{
        [self stopActivityIndicator];
    }];
}

- (void) startActivityIndicator {
    self.mediaPickerActivityIndicator.hidden = false;
    [self.mediaPickerActivityIndicator startAnimating];
}

- (void) stopActivityIndicator {
    self.mediaPickerActivityIndicator.hidden = true;
    [self.mediaPickerActivityIndicator stopAnimating];
}

- (void)playMediaItem: (MPMediaItem *) item {
    self.playStopButton.enabled = NO;
    [self startActivityIndicator];
    NSURL *assetURL = [item valueForProperty: MPMediaItemPropertyAssetURL];
    if (!assetURL) {
        NSLog(@"Asset does not exist!");
        return;
    }
    
    [self.player playAudioFileWithAssetURL:assetURL];

}

- (IBAction)playStopButtonPressed:(id)sender {
    if (self.player.playing) {
        [self.player stop];
        [sender setTitle:@"Play" forState:UIControlStateNormal];
    }
    else {
        [self startMediaPicker];
    }
}

#pragma mark - Drawing functions
- (void) setupSpectrumView {
    self.audioSpectrumView.spectrumColor = [UIColor redColor];
    self.audioSpectrumView.numBins = 128;
    [self hideSpectrumView:self.audioSpectrumView];
}

- (void)showSpectrumView: (GSASpectrumView*) view {
    view.hidden = false;
}

- (void)hideSpectrumView: (GSASpectrumView*) view {
    view.hidden = true;
}

- (void) drawSpectrumWithFFT: (NSArray<NSNumber*> *) fftArray {
    self.audioSpectrumView.spectrumData = fftArray;
    [self.audioSpectrumView setNeedsDisplay];
}

#pragma mark - MPMediaPickerControllerDelegate functions

- (void) mediaPicker:(MPMediaPickerController *)mediaPicker didPickMediaItems:(MPMediaItemCollection *)mediaItemCollection {
    [mediaPicker dismissViewControllerAnimated:YES completion:nil];
    self.playStopButton.enabled = YES;
    
    if ([mediaItemCollection count] < 1) {
        NSLog(@"No Media Items returned");
        return;
    }
    
    MPMediaItem *firstItem = [[mediaItemCollection items] firstObject];
    
     if ([[firstItem valueForKey:MPMediaItemPropertyIsCloudItem] integerValue] == 1) {
        NSLog(@"Item is a cloud media item");
        return;
    }
    
    [self playMediaItem: firstItem];

}

- (void) mediaPickerDidCancel:(MPMediaPickerController *)mediaPicker {
    [mediaPicker dismissViewControllerAnimated:YES completion:nil];
    self.playStopButton.enabled = YES;
}

#pragma mark - GSACoreAudioPlayerDelegate Functions
/**
 Delegate function called when playback finishes
 @param audioPlayer The audio player that is ready for playback
 @param successfully YES if the player finished playing the file, NO if it did not
 */
- (void) audioPlayerDidFinishPlaying: (GSACoreAudioPlayer *) audioPlayer successfully:(BOOL)flag {
    [self.playStopButton setTitle:@"Play" forState:UIControlStateNormal];
}

/**
 Delegate function called when playback is ready
 @param audioPlayer The audio player that is ready for playback
 */
- (void) audioPlayerPlaybackReady: (GSACoreAudioPlayer *) audioPlayer {
    self.playStopButton.enabled = YES;
    [self.playStopButton setTitle:@"Stop" forState:UIControlStateNormal];
    [self stopActivityIndicator];
    [self showSpectrumView: self.audioSpectrumView];
}

/**
 Delegate function called for processing audio data before it is sent to output device
 @param audioPlayer The audio player that is returning data
 @param didSendAudioBuffers The AudioBufferList to be sent to the output device
 */
- (void)audioPlayer: (GSACoreAudioPlayer *) audioPlayer didSendAudioBuffers: (AudioBufferList *) audioBufferList withFrames: (UInt32) numFrames atTimeStamp: (const AudioTimeStamp *) timeStamp {
    
    NSArray<NSNumber*> *fftArray = [self.fftRender renderFFTWithFrames:audioBufferList numFrames:numFrames];
    [self drawSpectrumWithFFT: fftArray];
}

@end
