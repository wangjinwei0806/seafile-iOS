//
//  SeafSettingsViewController.m
//  seafile
//
//  Created by Wang Wei on 10/27/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

#import "SeafAppDelegate.h"
#import "SeafDetailViewController.h"
#import "SeafSettingsViewController.h"
#import "SeafDirViewController.h"
#import "SeafRepos.h"
#import "SeafAvatar.h"
#import "UIViewController+Extend.h"
#import "FileSizeFormatter.h"
#import "ExtentedString.h"
#import "Debug.h"

enum {
    CELL_INVITATION = 0,
    CELL_WEBSITE,
    CELL_SERVER,
    CELL_VERSION,
};

enum {
    SECTION_ACCOUNT = 0,
    SECTION_CAMERA,
    SECTION_CACHE,
    SECTION_ABOUT,
    SECTION_WIPECACHE,
};
enum CAMERA_CELL{
    CELL_AUTO = 0,
    CELL_VIDEOS,
    CELL_WIFIONLY,
    CELL_BACKGROUND,
    CELL_DESTINATION,
};;

#define SEAFILE_SITE @"http://www.seafile.com"
#define MSG_RESET_UPLOADED NSLocalizedString(@"Do you want reset the uploaded photos?", @"Seafile")
#define MSG_CLEAR_CACHE NSLocalizedString(@"Are you sure to clear all the cache?", @"Seafile")

@interface SeafSettingsViewController ()<SeafDirDelegate, SeafPhotoSyncWatcherDelegate, MFMailComposeViewControllerDelegate, CLLocationManagerDelegate>
@property (strong, nonatomic) IBOutlet UITableViewCell *nameCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *usedspaceCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *serverCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *cacheCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *versionCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *autoSyncCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *syncRepoCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *tellFriendCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *websiteCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *videoSyncCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *backgroundSyncCell;

@property (strong, nonatomic) IBOutlet UILabel *wipeCacheLabel;
@property (strong, nonatomic) IBOutlet UILabel *autoCameraUploadLabel;
@property (strong, nonatomic) IBOutlet UILabel *wifiOnlyLabel;
@property (strong, nonatomic) IBOutlet UILabel *videoSyncLabel;
@property (strong, nonatomic) IBOutlet UILabel *backgroundSyncLable;

@property (strong, nonatomic) IBOutlet UISwitch *autoSyncSwitch;
@property (strong, nonatomic) IBOutlet UISwitch *wifiOnlySwitch;
@property (strong, nonatomic) IBOutlet UISwitch *videoSyncSwitch;
@property (strong, nonatomic) IBOutlet UISwitch *backgroundSyncSwitch;

@property (strong, nonatomic) CLLocationManager *locationManager;

@property int state;

@property NSString *version;
@end

@implementation SeafSettingsViewController

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (BOOL)autoSync
{
    return _connection.autoSync;
}

- (BOOL)wifiOnly
{
    return _connection.wifiOnly;
}

- (BOOL)videoSync
{
    return _connection.videoSync;
}

- (BOOL)backgroundSync
{
    return _connection.backgroundSync;
}

- (void)setAutoSync:(BOOL)autoSync
{
    if (_connection.autoSync == autoSync)
        return;
    _connection.autoSync = autoSync;
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate checkBackgroundUploadStatus];
}

- (void)setVideoSync:(BOOL)videoSync
{
    _connection.videoSync = videoSync;
}

- (void)setWifiOnly:(BOOL)wifiOnly
{
    _connection.wifiOnly = wifiOnly;
}

- (void)setBackgroundSync:(BOOL)backgroundSync
{
    _connection.backgroundSync = backgroundSync;
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate checkBackgroundUploadStatus];
}

- (void)checkPhotoLibraryAuthorizationStatus
{
    if([ALAssetsLibrary authorizationStatus] == ALAuthorizationStatusNotDetermined) {
        ALAssetsLibrary *assetLibrary = [[ALAssetsLibrary alloc] init];
        /*
         Enumerating assets or groups of assets in the library will present a consent dialog to the user.
         */
        [assetLibrary enumerateGroupsWithTypes:ALAssetsGroupAll usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
            self.autoSync = _autoSyncSwitch.on;
            *stop = true;
        } failureBlock:^(NSError *error) {
            _autoSyncSwitch.on = false;
        }];
    } else if([ALAssetsLibrary authorizationStatus] == ALAuthorizationStatusRestricted ||
              [ALAssetsLibrary authorizationStatus] == ALAuthorizationStatusDenied) {
        [self alertWithTitle:NSLocalizedString(@"This app does not have access to your photos and videos.", @"Seafile") message:NSLocalizedString(@"You can enable access in Privacy Settings", @"Seafile")];
        _autoSyncSwitch.on = false;
    } else if([ALAssetsLibrary authorizationStatus] == ALAuthorizationStatusAuthorized) {
        self.autoSync = _autoSyncSwitch.on;
    }
}

- (void)autoSyncSwitchFlip:(id)sender
{
    if (_autoSyncSwitch.on) {
        [self checkPhotoLibraryAuthorizationStatus];
    } else {
        self.autoSync = _autoSyncSwitch.on;
        _syncRepoCell.detailTextLabel.text = @"";
        [self.tableView reloadData];
        _connection.autoSyncRepo = nil;
        [_connection performSelectorInBackground:@selector(checkAutoSync) withObject:nil];
    }
}

- (void)wifiOnlySwitchFlip:(id)sender
{
    self.wifiOnly = _wifiOnlySwitch.on;
}

- (void)videoSyncSwitchFlip:(id)sender
{
    self.videoSync = _videoSyncSwitch.on;
    [_connection checkPhotoChanges:nil];
}

- (CLLocationManager *)locationManager {
    if (!_locationManager) {
        _locationManager = [[CLLocationManager alloc] init];
        _locationManager.delegate = self;
    }
    return _locationManager;
}
- (void)backgroundSyncSwitchFlip:(id)sender
{
    Debug("_backgroundSyncSwitch status:%d", _backgroundSyncSwitch.on);
    if (!_backgroundSyncSwitch.on) {
        self.backgroundSync = _backgroundSyncSwitch.on;
        return;
    }
    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
    Debug("AuthorizationStatus: %d", status);
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    if (status == kCLAuthorizationStatusNotDetermined) {
        if (ios8) {
            [self.locationManager requestAlwaysAuthorization];
        } else {
            [appdelegate startSignificantChangeUpdates];
        }
        return;
    }
    if (status != kCLAuthorizationStatusAuthorizedAlways && status != kCLAuthorizationStatusAuthorized) {
        [self alertWithTitle:NSLocalizedString(@"This app does not have access to your location service.", @"Seafile") message:NSLocalizedString(@"You can enable access in Privacy Settings", @"Seafile")];
        _backgroundSyncSwitch.on = false;
    } else {
        self.backgroundSync = true;
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    _nameCell.textLabel.text = NSLocalizedString(@"Username", @"Seafile");
    _usedspaceCell.textLabel.text = NSLocalizedString(@"Space Used", @"Seafile");
    _autoCameraUploadLabel.text = NSLocalizedString(@"Auto Camera Upload", @"Seafile");
    _videoSyncLabel.text = NSLocalizedString(@"Upload Videos", @"Seafile");
    _wifiOnlyLabel.text = NSLocalizedString(@"Wifi Only", @"Seafile");
    _backgroundSyncLable.text = NSLocalizedString(@"Background Upload", @"Seafile");

    _syncRepoCell.textLabel.text = NSLocalizedString(@"Upload Destination", @"Seafile");
    _cacheCell.textLabel.text = NSLocalizedString(@"Local Cache", @"Seafile");
    _tellFriendCell.textLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Tell Friends about %@", @"Seafile"), APP_NAME];
    _websiteCell.textLabel.text = NSLocalizedString(@"Website", @"Seafile");
    _websiteCell.detailTextLabel.text = @"www.seafile.com";
    _serverCell.textLabel.text = NSLocalizedString(@"Server", @"Seafile");
    _versionCell.textLabel.text = NSLocalizedString(@"Version", @"Seafile");
    _wipeCacheLabel.text = NSLocalizedString(@"Wipe Cache", @"Seafile");
    self.title = NSLocalizedString(@"Settings", @"Seafile");

    self.navigationController.navigationBar.tintColor = BAR_COLOR;
    [_autoSyncSwitch addTarget:self action:@selector(autoSyncSwitchFlip:) forControlEvents:UIControlEventValueChanged];
    [_wifiOnlySwitch addTarget:self action:@selector(wifiOnlySwitchFlip:) forControlEvents:UIControlEventValueChanged];
    [_videoSyncSwitch addTarget:self action:@selector(videoSyncSwitchFlip:) forControlEvents:UIControlEventValueChanged];
    [_backgroundSyncSwitch addTarget:self action:@selector(backgroundSyncSwitchFlip:) forControlEvents:UIControlEventValueChanged];

    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    _version = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
    _versionCell.detailTextLabel.text = _version;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    dispatch_async(dispatch_get_main_queue(), ^ {
        [self configureView];
    });
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (long long)cacheSize
{
    return [Utils folderSizeAtPath:[SeafGlobal.sharedObject applicationDocumentsDirectory]];
}

- (void)configureView
{
    if (!_connection)
        return;

    _nameCell.detailTextLabel.text = _connection.username;
    _serverCell.detailTextLabel.text = [_connection.address trimUrl];
    _autoSyncSwitch.on = self.autoSync;
    if (self.autoSync)
        [self checkPhotoLibraryAuthorizationStatus];
    _wifiOnlySwitch.on = self.wifiOnly;
    _videoSyncSwitch.on = self.videoSync;
    _backgroundSyncSwitch.on = self.backgroundSync;
    SeafRepo *repo = [_connection getRepo:_connection.autoSyncRepo];
    _syncRepoCell.detailTextLabel.text = repo ? repo.name : nil;

    long long cacheSize = [self cacheSize];
    _cacheCell.detailTextLabel.text = [FileSizeFormatter stringFromNumber:[NSNumber numberWithLongLong:cacheSize] useBaseTen:NO];
    Debug("%@, %lld, %lld, total cache=%lld", _connection.username, _connection.usage, _connection.quota, cacheSize);
    if (_connection.quota <= 0) {
        if (_connection.usage < 0)
            _usedspaceCell.detailTextLabel.text = @"Unknown";
        else
            _usedspaceCell.detailTextLabel.text = [FileSizeFormatter stringFromNumber:[NSNumber numberWithLongLong:_connection.usage] useBaseTen:NO];
    } else {
        float usage = 100.0 * _connection.usage/_connection.quota;
        NSString *quotaString = [FileSizeFormatter stringFromNumber:[NSNumber numberWithLongLong:_connection.quota ] useBaseTen:NO];
        if (usage < 0)
            _usedspaceCell.detailTextLabel.text = [NSString stringWithFormat:@"? of %@", quotaString];
        else
            _usedspaceCell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f%% of %@", usage, quotaString];
    }
    [self.tableView reloadData];
}

- (void)setConnection:(SeafConnection *)connection
{
    _connection = connection;
    [self.tableView reloadData];
    [_connection getAccountInfo:^(bool result, SeafConnection *conn) {
        if (result && conn == self.connection) {
            dispatch_async(dispatch_get_main_queue(), ^ {
                [self configureView];
                _connection.photSyncWatcher = self;
            });
        }
    }];
}

- (void)popupRepoSelect
{
    SeafDirViewController *c = [[SeafDirViewController alloc] initWithSeafDir:self.connection.rootFolder delegate:self chooseRepo:true];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:c];
    [navController setModalPresentationStyle:UIModalPresentationFormSheet];
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate.tabbarController presentViewController:navController animated:YES completion:nil];
}

#pragma mark - Table view delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:NO];
    if (indexPath.section == SECTION_ACCOUNT) {
        if (indexPath.row == 1) // Select the quota cell
            [_connection getAccountInfo:^(bool result, SeafConnection *conn) {
                if (result && conn == self.connection) {
                    dispatch_async(dispatch_get_main_queue(), ^ {
                        [self configureView];
                    });
                }
            }];
    } else if (indexPath.section == SECTION_CAMERA) {
        if (indexPath.row == CELL_DESTINATION && self.autoSync) {
            [self popupRepoSelect];
        }
    } else if (indexPath.section == SECTION_ABOUT) {
        _state = (int)indexPath.row;
        switch ((indexPath.row)) {
            case CELL_INVITATION:
                [self sendMailInApp];
                break;

            case CELL_WEBSITE:
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:SEAFILE_SITE]];
                break;

            case CELL_SERVER:
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/", _connection.address]]];
                break;

            default:
                break;
        }
    } else if (indexPath.section == SECTION_WIPECACHE) {
        [self alertWithTitle:MSG_CLEAR_CACHE message:nil yes:^{
            SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
            [(SeafDetailViewController *)[appdelegate detailViewControllerAtIndex:TABBED_SETTINGS] setPreViewItem:nil master:nil];
            [Utils clearAllFiles:SeafGlobal.sharedObject.objectsDir];
            [Utils clearAllFiles:SeafGlobal.sharedObject.blocksDir];
            [Utils clearAllFiles:SeafGlobal.sharedObject.editDir];
            [Utils clearAllFiles:SeafGlobal.sharedObject.thumbsDir];
            [Utils clearAllFiles:SeafGlobal.sharedObject.tempDir];
            [SeafUploadFile clearCache];
            [SeafAvatar clearCache];

            [[SeafGlobal sharedObject] deleteAllObjects:@"Directory"];
            [[SeafGlobal sharedObject] deleteAllObjects:@"DownloadedFile"];
            [[SeafGlobal sharedObject] deleteAllObjects:@"SeafCacheObj"];

            long long cacheSize = [self cacheSize];
            _cacheCell.detailTextLabel.text = [FileSizeFormatter stringFromNumber:[NSNumber numberWithLongLong:cacheSize] useBaseTen:NO];

        } no:nil];
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString *sectionNames[] = {
        NSLocalizedString(@"Account Info", @"Seafile"),
        NSLocalizedString(@"Auto Camera Upload", @"Seafile"),
        NSLocalizedString(@"Cache", @"Seafile"),
        NSLocalizedString(@"About", @"Seafile"),
        @"",
    };
    if (section < SECTION_ACCOUNT || section > SECTION_WIPECACHE)
        return nil;
    if (section == SECTION_CAMERA && _connection.inAutoSync) {
        NSUInteger num = _connection.photosInSyncing;
        NSString *remainStr = @"";
        if (num == 0) {
            remainStr = NSLocalizedString(@"All photos synced", @"Seafile");
        } else if (num == 1) {
            remainStr = NSLocalizedString(@"1 photo remain", @"Seafile");
        } else {
            remainStr = [NSString stringWithFormat:NSLocalizedString(@"%ld photos remain", @"Seafile"), num];
        }
#if DEBUG
        remainStr = [remainStr stringByAppendingFormat:@"  U:%ld D:%ld", (long)SeafGlobal.sharedObject.uploadingnum, (long)SeafGlobal.sharedObject.downloadingnum];
#endif
        return [sectionNames[section] stringByAppendingFormat:@"\t %@", remainStr];
    }
#if DEBUG
    else if (section == SECTION_CAMERA) {
        NSString *remainStr = [NSString stringWithFormat:@"  U:%ld D:%ld", (long)SeafGlobal.sharedObject.uploadingnum, (long)SeafGlobal.sharedObject.downloadingnum];
        return [sectionNames[section] stringByAppendingFormat:@"\t %@", remainStr];
    }
#endif
    return sectionNames[section];
}

- (void)viewDidUnload {
    [self setNameCell:nil];
    [self setUsedspaceCell:nil];
    [self setServerCell:nil];
    [self setCacheCell:nil];
    [self setVersionCell:nil];
    [super viewDidUnload];
}


#pragma mark - sena mail inside app
- (void)sendMailInApp
{
    Class mailClass = NSClassFromString(@"MFMailComposeViewController");
    if (!mailClass) {
        [self alertWithTitle:NSLocalizedString(@"This function is not supportted yet", @"Seafile")];
        return;
    }
    if (![mailClass canSendMail]) {
        [self alertWithTitle:NSLocalizedString(@"The mail account has not been set yet", @"Seafile")];
        return;
    }
    [self displayMailPicker];
}

- (void)configureInvitationMail:(MFMailComposeViewController *)mailPicker
{
    [mailPicker setSubject:[NSString stringWithFormat:NSLocalizedString(@"%@ invite you to %@", @"Seafile"), NSFullUserName(), APP_NAME]];
    NSString *emailBody = [NSString stringWithFormat:NSLocalizedString(@"Hey there!<br/><br/> I've been using %@ and thought you might like it. It is a free way to bring all you files anywhere and share them easily.<br/><br/>Go to the official website of %@:</br></br> <a href=\"%@\">%@</a>\n\n", @"Seafile"), APP_NAME, APP_NAME, SEAFILE_SITE, SEAFILE_SITE];

    [mailPicker setMessageBody:emailBody isHTML:YES];
}

- (void)displayMailPicker
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    MFMailComposeViewController *mailPicker = appdelegate.globalMailComposer;
    mailPicker.mailComposeDelegate = self;
    [self configureInvitationMail:mailPicker];
    [appdelegate.tabbarController presentViewController:mailPicker animated:YES completion:nil];
}

#pragma mark - MFMailComposeViewControllerDelegate
- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error
{
    NSString *msg;
    switch (result) {
        case MFMailComposeResultCancelled:
            msg = @"cancalled";
            break;
        case MFMailComposeResultSaved:
            msg = @"saved";
            break;
        case MFMailComposeResultSent:
            msg = @"sent";
            break;
        case MFMailComposeResultFailed:
            msg = @"failed";
            break;
        default:
            msg = @"";
            break;
    }
    Debug("state=%d:send mail %@\n", _state, msg);
    [self dismissViewControllerAnimated:YES completion:^{
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate cycleTheGlobalMailComposer];
    }];
}

#pragma mark - SeafDirDelegate
- (void)setSyncRepo:(SeafRepo *)repo
{
    _connection.autoSyncRepo = repo.repoId;
    _syncRepoCell.detailTextLabel.text = repo.name;
    [_connection performSelectorInBackground:@selector(checkAutoSync) withObject:nil];
    [self.tableView reloadData];
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appdelegate checkBackgroundUploadStatus];
}

- (void)chooseDir:(UIViewController *)c dir:(SeafDir *)dir
{
    [c.navigationController dismissViewControllerAnimated:YES completion:nil];
    NSString *old = _connection.autoSyncRepo;
    SeafRepo *repo = (SeafRepo *)dir;
    if ([repo.repoId isEqualToString:old]) {
        [_connection checkPhotoChanges:nil];
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^ {
        [self alertWithTitle:MSG_RESET_UPLOADED message:nil yes:^{
            [_connection resetUploadedPhotos];
            [self setSyncRepo:repo];
        } no:^{
            [self setSyncRepo:repo];
        }];
    });
}

- (void)cancelChoose:(UIViewController *)c
{
    [c.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - SeafPhotoSyncWatcherDelegate
- (void)photoSyncChanged:(long)remain
{
    Debug("%ld photos remain to uplaod", remain);
    if (self.isVisible)
        [self.tableView reloadData];
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
    Debug("AuthorizationStatus: %d", status);
    if (status != kCLAuthorizationStatusAuthorizedAlways && status != kCLAuthorizationStatusAuthorized) {
        _backgroundSyncSwitch.on = false;
    } else {
        _backgroundSyncSwitch.on = true;
        self.backgroundSync = true;
    }
}

@end
