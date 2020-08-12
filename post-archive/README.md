Post-Archive Integration
========================

The Idea
--------

We want to record BigBlueButton meetings.  
But we don't want process and publish them through BBB, but with Opencast.  
So we send all the raw recording data from BBB to Opencast and process them with an Opencast workflow.  

Requirements
--------
- Opencast 8.4 (or later)
- BigBlueButton 2.2 (or later)
	- Ruby gems: rest-client, fileutils, mini_magick

Files:
--------
post_archive.rb: A ruby script that handles sending data from BBB to Opencast.  
bbb-upload.xml: An example workflow for Opencast. Based off the "fast" workflow. 

Setup BBB
--------
- If the required ruby gems are not yet installed, manually install the ruby gems mentioned under requirements via `gem install *name*`. They are used by the post_archive.rb script.
- Place the script `post_archive.rb` in 
    
    `/usr/local/bigbluebutton/core/scripts/post_archive/`
- In the script `post_archive.rb`, change the global variables in the "opencast configuration":
	- In `post_archive.rb`, change the variable `$oc_server` to point to your Opencast installation
	- Also change `$oc_user` and `oc_password` to a user of your opencast installation that is allowed to ingest (e.g. ROLE_ADMIN, ROLE_STUDIO)
	    - If you want to be able to create new Opencast series from BBB, the user NEEDS to have ROLE_ADMIN.
	- Change the remaining options how you like.
- Disable the process and publish steps by calling: `sudo bbb-record --disable presentation`
- Allow post scripts to call the `bbb-record` utility by adding the line `bigbluebutton ALL = NOPASSWD: /usr/bin/bbb-record` to `/etc/sudoers`
- Ensure BBB is configured for recording. In `/usr/share/bbb-web/WEB-INF/classes/bigbluebutton.properties` the parameter `disableRecordingDefault` should be set to false.
	- In the same file, set `autoStartRecording` to true and `allowStartStopRecording` to false to reflect the current limitations.
	- For changes in bigbluebutton.properties to take effect, BBB needs to be restarted using `bbb-conf --restart`

Setup Opencast
--------
- In your Opencast installation, add the file `bbb-upload.xml` to the workflow folder (Likely located at `etc/workflows` or `etc/opencast/workflows`)

Limitations & Take Cares
--------
- Currently, only audio, deskshare, raw slides (no marks) and one webcam file are transmitted. 
- After successfully transmitting the data to Opencast, all recording related data on the BBB installation WILL BE DELETED!
	- If you don't want that, comment out the line under the comment `# Delete all raw recording data` in the function `cleanup`
- Currently processes and publishes the WHOLE conference, not just when you click the start/stop recording button
	- To get rid of the parts you don't want, use the video editor tool in Opencast
- The recording is published with a few default metadata values. To set further metadata, the frontend which creates the BBB-Meeting will need pass them when calling the `/create` API, so that BBB then may pass them on to Opencast. An overview over the possible metadata can be found [here](https://github.com/elan-ev/opencast-bigbluebutton-integration).

Troubleshooting
--------
1. Opencast didn't get any data
	- Check the logs
		- `/var/log/bigbluebutton/bbb-rap-worker.log`, for potential exceptions
		- `/var/log/bigbluebutton/post_archive.log`, for additional information
	- Secure the recording data 
		- Or else it might get lost during regularly scheduled clean-ups
		- `/var/bigbluebutton/recording/raw/` is where the raw recording data is stored
	- If the problem could be resolved, try again
		- Run `sudo bbb-record --rebuild *path/to/recording*` on your BBB installation
		- `/var/bigbluebutton/recording/raw/` is where the raw recording data is stored
2. Opencast failed
	- ...
