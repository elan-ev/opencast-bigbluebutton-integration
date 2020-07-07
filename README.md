# Opencast BigBlueButton Integration
Documentation for sending recordings from BigBlueButton to Opencast

Dublincore Metadata Definition
-------------------

BigBlueButtons create-API allows the passing of metadata for each meeting. This can be used to pass metadata to BigBlueButton which should later appear in the recording in Opencast. The list below defines which metadata is passed.
*Usage of upper and lower case letters does not matter*

- opencast-dc-title
    - Description: Title of the Opencast episode
    - Default: Room name
- opencast-dc-identifier
    - Description: Media package and event identifier
    - Default: Meeting ID or None (Configurable)
- opencast-dc-creator
    - Description: The person primary reponsible for the creation of the event
    - May appear multiple times *** Geht das?
    - Default: None or Every moderator (Configurable)
- opencast-dc-isPartOf
    - Desctiption: Series identifier of which the event is part of
    - Default: None
- opencast-dc-contributor
    - Description: People contributing to the event
    - May appear multiple times *** Geht das?
    - Default: None or every viewer (Configurable)
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


User access data
----------------

- opencast-acl-user-id
    - user gets read and write access via acl
    - Default: Meeting owner ID
- opencast-acl-read-roles
    - Example: ROLE_USER,ROLE_XY
- opencast-acl-write-roles
    - Example: ROLE_XY
