# Profile images

Every user can set a profile image. It shows wherever a person appears, so the "With" list, comments, the feed,
people search and profile pages stop being rows of names. Without an image the app shows the person's initial in a
round tinted circle, as it does today.

## What the owner wants

- A profile image for every user (optional, nobody is forced to set one).
- It makes the friends on a flight (the avatar next to the name) more useful and nicer to look at.
- Same on iOS and Android.

## Decisions

| Question | Decision | Why |
| --- | --- | --- |
| Where do images live? | A new public Storage bucket `avatars`, one object per user: `<user id>/avatar.jpg`. | Names and usernames are already visible to every signed-in user, so the picture is no more private. A public bucket needs no signed links, which keeps lists with many people fast and cacheable. |
| Who may write? | Only the owner, in their own folder (read, insert, update, delete policies, like the photo bucket). The read rule is needed to replace a file and keeps others from listing folders. | Same pattern as `photos`. |
| Limits | JPEG only, 512 KB, enforced by the bucket. | Keeps traffic small. |
| What does the phone upload? | A square centre crop, 512 x 512, re-encoded as JPEG. Re-encoding drops location and camera data. | Nothing private leaves the phone, and every avatar is the same size. |
| Is the address stored? | `profiles.avatar_url` (the column exists and is already readable and writable) holds the public address with `?v=<unix seconds>`. It is `null` without an image. | The person page and your own profile read the profile row anyway. Lists use the fixed address of the user's folder, see below. |
| How do lists find an image? | The address of a user's image is always `<storage>/object/public/avatars/<user id>/avatar.jpg`. The app asks for it and falls back to the initial if there is none. A miss is remembered for the session, so a feed of 30 check-ins asks once per person. | No extra column in the feed, comment or tag functions, so none of them change. |
| Changed images | The object is replaced with a cache lifetime of 5 minutes. Your own phone adds a version to the address so you see the new image at once. Others see it within about 5 minutes. | Simple, and no cache busting service needed. |
| Cropping UI | None in the first version (automatic centre crop). | Keeps the change small. Can come later. |
| Remove | "Remove photo" deletes the object and clears `avatar_url`. | |
| Account deletion | The `me` function removes the user's avatar folder together with the photo folder. | The account deletion promise stays true. |
| Moderation | The existing "Report person" flow stays. Someone with the service key can delete an object. | No new moderation tool for now. |

## Where it shows

1. Profile tab header and the edit-profile screen (choose and remove).
2. Person page header.
3. "With" rows on a check-in, and the friend picker rows.
4. Comments.
5. Feed cards (small, next to the author name).
6. People search and the lists of people you follow.

## Delivery steps

1. **Backend.** Migration for the bucket and its policies, pgTAP test, deletion in the `me` function. Not deployed
   without the owner's word.
2. **iOS.** An `Avatar` view (image, initial as fallback, in-memory and URL cache, remembered misses), the picker and
   upload in the profile editor, then use it in the places above.
3. **Android.** The same, with the same look.
4. **Check.** Both apps on a simulator or emulator against the local stack, tests green, then a build for the testers.

## Not in this version

A crop or zoom screen, filters, animated images, hiding the picture from some people, showing the picture in push
notifications.
