# G RECOVERY / STORE COPY

Everything that goes into Play Console, written to be pasted. Nothing here is a
draft to be reworded later: the permission declarations are judged on whether the
stated use matches what the app does, so the wording IS the commitment.

---

## Listing

Free, no ads, no in-app purchases (Pro retired in 3.0.0). Written to be pasted.
Short description is 75 of 80 characters, full description 2297 of 4000.

**Title (30 char limit):**

    G Recovery: All in One Toolkit

**Short description (80 char limit):**

    Recover deleted photos and files, test your phone's speed, free up storage.

**Full description (4000 char limit):**

```
G Recovery finds what you deleted, shows how fast your phone really is, and helps you take back storage. Free, with no ads and no account.

RECOVER DELETED FILES
• Looks in the system trash, gallery and file manager trash folders, and app trash folders
• Shows a preview first, so you know it is the right file before restoring
• Tells you how long each file has left before it is gone for good
• Finds photos that only survive as thumbnails, and says so before you restore
• Message archive: switch it on and incoming chat messages are kept, so a message deleted later can still be read

BENCHMARK YOUR PHONE
• Tests the processor on one core and on every core, graphics, memory and storage
• An x-ray of your own phone lights up each part as it is tested
• Results in plain words: how fast apps open, how games will run, how quickly photos save
• A score you can compare: 1000 is a Galaxy S22
• See where your phone ranks among popular phones, from budget models to the latest flagships
• Every run is saved, so you can see if your phone slows down over time

KNOW YOUR PHONE
• Battery health, temperature and charging
• Processor, memory, display, cameras, sensors, network and SIM details
• Screen test for dead pixels, speaker and vibration test, touch test

FREE UP STORAGE
• See what is using your space, by category and by folder
• Find exact duplicates, similar photos, blurry shots and large old files
• Make photos and videos smaller without lowering their resolution, with a before and after to check
• Nothing is removed until you confirm it

BACK UP TO YOUR OWN SERVER
• Copy photos and files to your own computer or NAS over SMB, WebDAV or Nextcloud
• Every file is checked after it is copied
• Your password stays encrypted on your phone

PRIVATE BY DESIGN
• Everything runs on your phone. Your photos and files are never uploaded
• No account, no ads, nothing to buy
• Setup notes for Samsung, Xiaomi, Redmi, Tecno and Infinix phones, where trash folders work differently

PERMISSIONS
• All files access reaches the trash folders other apps keep, which no narrower permission can see
• Installed apps and usage access show how much space each app takes
• Notification access is used only by the message archive, and only after you switch it on
None of these are used for tracking.
```

---

## Photo and video permissions declaration

Both under the 250 character limit. Both end on "never uploaded", which is true,
is the first thing a reviewer wonders about a media-reading app, and costs nine
characters.

### READ_MEDIA_IMAGES

    G Recovery lists photos in the system trash and in app trash folders so
    users can restore them, shows thumbnails so a file is recognisable before
    restoring, and reports how much space images use so storage can be freed.
    Images are never uploaded.

### READ_MEDIA_VIDEO

    G Recovery lists videos in the system trash and in app trash folders so
    users can restore them, plays a video so it can be identified before
    restoring, and reports how much space video uses so users can free storage.
    Videos are never uploaded.

---

## Still open, and each one blocks a release

- **K1.** The live listing declares "Contains ads" for an app that has none and
  never will. This is a wrong statement on a public listing and takes minutes to
  correct.
- **K2.** The icon is a stock trash can shared with about nine competitors.
- **K3.** Store screenshots show `0 Files`.
- **K6.** Upload keystore location and the live versionCode have never been
  written down anywhere.
- MANAGE_EXTERNAL_STORAGE needs its own declaration, separate from the two
  above, and it is the one most likely to draw questions. The answer is the same
  as the permission text: app trash folders belong to other apps, and no narrower
  permission reaches them.
