Opencast BigBlueButton Integration
==================================

_Documentation for sending recordings from BigBlueButton to Opencast._

This repository contains documentation and BigBlueButton processing scripts suitable for different scenarios.
Make sure to read through the different options and evaluate which integration best fits your use-case.

- [Post-publish Integration](post-publish) – This integration leverages the recording processing capabilities of BigBlueButton to then transfer the processed video files to Opencast.
  The advantage is that this integration is relatively small and easy to use. The downside is that a lot of the processing happens on the BigBlueButton servers,
  taking away processing power from your next video conference.

- [Post-archive Integration](post-archive) – This integration sends the raw recording data from a BigBlueButton Meeting to Opencast and relies on Opencast itself to process it.
  This reduces the load on BigBlueBUtton servers which could otherwise decrease audio and video quality for further conferences. However, this solution is less feature complete, as Opencast still needs to be taught how to properly process webconferencing data.


Dublincore Metadata Definition
-------------------

BigBlueButtons create-API allows the passing of metadata for each meeting. This can be used to pass metadata to BigBlueButton which should later appear in the recording in Opencast. The list below defines which metadata is passed.
*Usage of upper and lower case letters does not matter*

- opencast-dc-title
    - Description: Title of the Opencast episode
    - Default: Room name
- opencast-dc-identifier
    - Description: Media package and event identifier. Has to be a valid UUID.
    - Default: None
- opencast-dc-creator
    - Description: The person primary reponsible for the creation of the event
    - Default: None
- opencast-dc-isPartOf
    - Description: Series identifier of which the event is part of
    - Default: None
- opencast-dc-contributor
    - Description: People contributing to the event
    - Default: None
- opencast-dc-subject
    - Description: A topic of the event
    - Default: None
- opencast-dc-language
    - Description: The primary language. Language codes at the [Opencast repository](https://github.com/opencast/opencast/blob/develop/etc/listproviders/languages.properties).
    - Default: None
- opencast-dc-description
    - Description: Description of the event
    - Default: None or shared notes (Configurable)
- opencast-dc-spatial
    - Description: Location of the event
    - Default: "BigBlueButton"
- opencast-dc-created
    - Description: Date of the event
    - Default: Meeting start date
- opencast-dc-rightsHolder
    - Description: Rights holder of the resulting video
    - Default: None
- opencast-dc-license
    - Description: License of the resulting video. License codes at the [Opencast repository](https://github.com/opencast/opencast/blob/develop/etc/listproviders/licenses.properties).
    - Default: None
- opencast-dc-publisher
    - Description: An entity responsible for making the resource available.
    - Default: None


#### User access data

- opencast-acl-user-id
    - user gets read and write access via acl
    - Default: None
- opencast-acl-read-roles
    - Example: ROLE_USER,ROLE_XY
- opencast-acl-write-roles
    - Example: ROLE_XY


Series Metadata Definition
----------------

If a UID for a series is provided in `opencast-dc-isPartOf`, but that series does not exist yet, it is possible for a new series to be created with which the recording can then be associated. The list below defines which metadata can be passed along to the series.

- opencast-series-dc-title
    - Description: Title of the Opencast series
    - Default: Room name
- opencast-series-dc-creator
    - Description: The persons primary reponsible for the creation of the event
    - Default: None
- opencast-series-dc-contributor
    - Description: People contributing to the event
    - Default: None
- opencast-series-dc-subject
    - Description: A topic of the event
    - Default: None
- opencast-series-dc-language
    - Description: The primary language. Language codes at the [Opencast repository](https://github.com/opencast/opencast/blob/develop/etc/listproviders/languages.properties).
    - Default: None
- opencast-series-dc-description
    - Description: Description of the event
    - Default: None
- opencast-series-dc-rightsHolder
    - Description: Rights holder of the resulting video
    - Default: None
- opencast-series-dc-license
    - Description: License of the resulting video. License codes at the [Opencast repository](https://github.com/opencast/opencast/blob/develop/etc/listproviders/licenses.properties).
    - Default: None
- opencast-series-dc-publisher
    - Description: Entities responsible for making the resource available.
    - Default: None


#### Series user access data

An addition to the ACLs of the meeting, the series can have its own ACLs as well.

- opencast-series-acl-user-id
    - user gets read and write access via acl
    - Default: None
- opencast-series-acl-read-roles
    - Example: ROLE_USER,ROLE_XY
- opencast-series-acl-write-roles
    - Example: ROLE_XY


Parameters
----------------

Various parameters that change the behaviour of the integrations.
- opencast-add-webcams
  - Boolean on whether webcams should be sent to Opencast
  - Important: The post-archive integration also has this a global configuration option. If that is set to false, the parameter will be ignored!
  - Default for post-publish: true
  - Default for post-archive: The global configuration option
