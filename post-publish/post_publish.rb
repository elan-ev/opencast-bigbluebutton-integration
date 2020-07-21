#!/usr/bin/ruby
# encoding: UTF-8

#
# BigBlueButton open source conferencing system - http://www.bigbluebutton.org/
#
# Copyright (c) 2012 BigBlueButton Inc. and by respective authors (see below).
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the Free
# Software Foundation; either version 3.0 of the License, or (at your option)
# any later version.
#
# BigBlueButton is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
# details.
#
# You should have received a copy of the GNU Lesser General Public License along
# with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.
#

require "shellwords"
require "trollop"
require File.expand_path('../../../lib/recordandplayback', __FILE__)

opts = Trollop::options do
  opt :meeting_id, "Meeting id to archive", :type => String
end
meeting_id = opts[:meeting_id]

### opencast configuration begin

# Server URL
# oc_server = 'https://develop.opencast.org'
oc_server = 'https://develop.opencast.org'

# User credentials allowed to ingest via HTTP basic
# oc_user = 'username:password'
oc_user = 'admin:opencast'

# Workflow to use for ingest
# oc_workflow = 'schedule-and-upload'
oc_workflow = 'schedule-and-upload'

### opencast configuration end


logger = Logger.new("/var/log/bigbluebutton/post_publish.log", 'weekly' )
logger.level = Logger::INFO
BigBlueButton.logger = logger

published_files = "/var/bigbluebutton/published/presentation/#{meeting_id}"
meeting_metadata = BigBlueButton::Events.get_meeting_metadata("/var/bigbluebutton/recording/raw/#{meeting_id}/events.xml")

#
# Put your code here
#
BigBlueButton.logger.info("Upload Recording for [#{meeting_id}]...")

ingest = false
presenter = ''
presentation = ''
title = Shellwords.escape(meeting_metadata['meetingName'])
oc_user = Shellwords.escape(oc_user)

if (File.exists?(published_files + '/video/webcams.webm'))
  BigBlueButton.logger.info("Found presenter video")
  ingest = true
  presenter = "-F 'flavor=presentater/source' -F 'BODY1=@#{published_files + '/video/webcams.webm'}'"
end
if (File.exists?(published_files + '/deskshare/deskshare.webm'))
  BigBlueButton.logger.info("Found presentation video")
  ingest = true
  presentation = "-F 'flavor=presentation/source' -F 'BODY2=@#{published_files + '/deskshare/deskshare.webm'}'"
end
if (ingest)
  BigBlueButton.logger.info("Uploading...")
  puts `curl -u '#{oc_user}' "#{oc_server}/ingest/addMediaPackage/#{oc_workflow}" #{presenter} #{presentation} -F title="#{title}"`
end
BigBlueButton.logger.info("Upload for [#{meeting_id}] ends")

exit 0
