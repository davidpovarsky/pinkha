# ChavrusaNotes signing and capability architecture

Apple Developer Team: `NA6HPWARQ2`

## Shipping identifiers

| Target | Bundle ID | Shared containers |
| --- | --- | --- |
| Main app | `com.itorah.chavrusanotes` | private + shared iTorah App Groups, iCloud |
| Share extension | `com.itorah.chavrusanotes.share` | private + shared iTorah App Groups |
| Widgets and Controls | `com.itorah.chavrusanotes.widgets` | private + shared iTorah App Groups |

- Private App Group: `group.com.itorah.chavrusanotes`
- Cross-product iTorah App Group: `group.com.itorah.shared`
- iCloud Drive and CloudKit container: `iCloud.com.itorah.chavrusanotes`

Every shipping target uses its own explicit App Store distribution profile.
The Release settings in `project.yml` map those profiles through
`CHAVRUSANOTES_MAIN_PROFILE`, `CHAVRUSANOTES_SHARE_PROFILE`, and
`CHAVRUSANOTES_WIDGETS_PROFILE`; CI never applies one profile globally.

## Reserved extension namespace

These identifiers are reserved in the architecture, but are not registered or
built until product code needs them:

- `com.itorah.chavrusanotes.notification-service`
- `com.itorah.chavrusanotes.notification-content`
- `com.itorah.chavrusanotes.quicklook-preview`
- `com.itorah.chavrusanotes.quicklook-thumbnail`

Live Activities remain in the WidgetKit extension when a concrete live state
exists. Notification and Quick Look targets must not be added before there is a
payload transformation, notification UI, or exported document format to serve.
No associated-domain entitlement is declared until an iTorah HTTPS domain and
`apple-app-site-association` file actually exist.

The sibling text application may later use `com.itorah.chavrusatext`; it is not
part of this project's provisioning set.
