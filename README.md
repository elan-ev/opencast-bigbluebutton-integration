# Opencast BigBlueButton Integration

This repository contains [BigBlueButton](https://bigbluebutton.org/) processing scripts as well as documentation
to configure BigBlueButton to send recordings to [Opencast](https://opencast.org/) under two different workflow scenarios.
Make sure to read through the different options and evaluate which integration best fits your use case.

- **[Post-publish Integration](post-publish)** – This integration leverages the recording processing capabilities of BigBlueButton to then transfer the processed video files to Opencast.
The **advantage** is that this integration is relatively small and easy to use.
The **downside** is that a lot of the processing happens on the BigBlueButton servers, taking away processing power from your next video conference.

- **[Post-archive Integration](post-archive)** – This integration sends the raw recording data from a BigBlueButton Meeting to Opencast and relies on Opencast itself to process it.
The **advantage** of this is that it reduces the load on BigBlueButton servers.
The **downside** of this is that this solution is less feature complete, as Opencast still needs to be taught how to properly process webconferencing data.

Possibly helpful ressources might also be the [BigBlueButton documentation on recordings](https://docs.bigbluebutton.org/dev/recording.html)
and the [Opencast documentation on workflows](https://docs.opencast.org/develop/admin/#configuration/workflow/).

## Installation

Generally, for this integration to work you need to configure and **install the processing scripts** on your BigBlueButton servers
and **adjust the workflows** accordingly in your Opencast installation.
For details consult the readmes in the respective subfolders to understand how to set up each scenario.
For the installation and configuration on your BigBlueButton servers you can also use the [ansible-role](https://galaxy.ansible.com/elan/bbb_opencast_integration).

## Opencast Metadata and Parameters

You can pass meeting metadata and other parameters to Opencast through the [create-API-call](https://docs.bigbluebutton.org/dev/api.html#create) from BigBlueButton.
This metadata should then later appear in the Opencast recordings.
The followings lists illustrate which metadata can be passed.

*Note that these values are **not** case sensitive*.

### Dublincore Metadata Definition

| Variable | Default Value | Description |
|:--|:--|:--|
| `opencast-dc-title` | Room name | Title of the Opencast episode |
| `opencast-dc-identifier` | None | Media package and event identifier, has to be a valid UUID |
| `opencast-dc-creator` | None | The person primary reponsible for the creation of the event |
| `opencast-dc-isPartOf` | None | Series identifier of which the event is part of |
| `opencast-dc-contributor` | None | People contributing to the event |
| `opencast-dc-subject` | None | A topic of the event |
| `opencast-dc-language` | None | The primary language, language codes can be found in the [Opencast repository](https://github.com/opencast/opencast/blob/develop/etc/listproviders/languages.properties) |
| `opencast-dc-description` | None or shared notes (configurable) | Description of the event |
| `opencast-dc-spatial` | "BigBlueButton" | Location of the event |
| `opencast-dc-created` | Meeting start date | Date of the event |
| `opencast-dc-rightsHolder` | None | Rights holder of the resulting video |
| `opencast-dc-license` | None | License of the resulting video, license codes can be found in the [Opencast repository](https://github.com/opencast/opencast/blob/develop/etc/listproviders/licenses.properties) |
| `opencast-dc-publisher` | None | An entity responsible for making the resource available |

#### User access data

| Variable | Default Value | Description |
|:--|:--|:--|
| `opencast-acl-user-id` | None | User that gets read and write access via ACL |
| `opencast-acl-read-roles` | Example: `ROLE_USER,ROLE_X` | Roles that can read |
| `opencast-acl-write-roles` | Example: `ROLE_XY` | Roles that can write |

### Series Metadata Definition

If a UID for a series is provided in `opencast-dc-isPartOf`, but that series does not exist yet, it is possible for a new series to be created with which the recording can then be associated. The list below defines which metadata can be passed along to the series.

| Variable | Default Value | Description |
|:--|:--|:--|
| `opencast-series-dc-title` | Room name | Title of the Opencast serie |
| `opencast-series-dc-creator` | None | The persons primary reponsible for the creation of the event |
| `opencast-series-dc-contributor` | None | People contributing to the event |
| `opencast-series-dc-subject` | None | A topic of the event |
| `opencast-series-dc-language` | None | The primary language, language codes can be found in the [Opencast repository](https://github.com/opencast/opencast/blob/develop/etc/listproviders/languages.properties) |
| `opencast-series-dc-description` | None | Description of the event |
| `opencast-series-dc-rightsHolder` | None | Rights holder of the resulting video |
| `opencast-series-dc-license` | None | License of the resulting video, license codes can be found in the [Opencast repository](https://github.com/opencast/opencast/blob/develop/etc/listproviders/licenses.properties) |
| `opencast-series-dc-publisher` | None | Entities responsible for making the resource available |

#### Series user access data

An addition to the ACLs of the meeting, the series can have its own ACLs as well.

| Variable | Default Value | Description |
|:--|:--|:--|
| `opencast-series-acl-user-id` | None | User that gets read and write access via ACL |
| `opencast-series-acl-read-roles` | Example: `ROLE_USER,ROLE_X` | Roles that can read |
| `opencast-series-acl-write-roles` | Example: `ROLE_XY` | Roles that can write |

### Other Parameters

Various parameters that change the behaviour of the integrations.

- `opencast-add-webcams`:
  - Boolean on whether webcams should be sent to Opencast
  - Important: The post-archive integration also has this a global configuration option. If that is set to false, the parameter will be ignored!
  - Default for post-publish: `true`
  - Default for post-archive: The global configuration option
