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
require "optimist"
require 'nokogiri'        #XML-Parser
require File.expand_path('../../../lib/recordandplayback', __FILE__)

require_relative 'oc_modules/oc_dublincore'
require_relative 'oc_modules/oc_acl'
require_relative 'oc_modules/oc_util'

### opencast configuration begin

# Server URL
# oc_server = 'https://develop.opencast.org'
oc_server = '{{opencast_server}}'

# User credentials allowed to ingest via HTTP basic
# oc_user = 'username:password'
oc_user = 'admin'
oc_password = 'opencast'

# Workflow to use for ingest
# oc_workflow = 'schedule-and-upload'
oc_workflow = 'schedule-and-upload'

# Default roles for the event, e.g. "ROLE_OAUTH_USER, ROLE_USER_BOB"
# Suggested default: ""
defaultRolesWithReadPerm = ""
defaultRolesWithWritePerm = ""

# Whether a new series should be created if the given one does not exist yet
# Suggested default: false
createNewSeriesIfItDoesNotYetExist = true

# Default roles for the series, e.g. "ROLE_OAUTH_USER, ROLE_USER_BOB"
# Suggested default: ""
defaultSeriesRolesWithReadPerm = ""
defaultSeriesRolesWithWritePerm = ""

### opencast configuration end

#
# Parse cmd args from BBB and initialize logger

opts = Optimist::options do
 opt :meeting_id, "Meeting id to archive", :type => String
 opt :file_type, "File type", :type => String
end
meeting_id = opts[:meeting_id]

logger = Logger.new("/var/log/bigbluebutton/post_publish.log", 'weekly' )
logger.level = Logger::INFO
BigBlueButton.logger = logger

published_files = "/var/bigbluebutton/published/presentation/#{meeting_id}"
meeting_metadata = BigBlueButton::Events.get_meeting_metadata("/var/bigbluebutton/recording/raw/#{meeting_id}/events.xml")

# Variables
DEFAULT_REQUEST_TIMEOUT = 10                                  # Http request timeout in seconds
START_WORKFLOW_REQUEST_TIMEOUT = 6000                         # Specific timeout; Opencast runs MediaInspector on every file, which can take quite a while
ACL_PATH = File.join(published_files, "acl.xml")

BigBlueButton.logger.info( "Prepare Metadata for [#{meeting_id}]...")

# Check parameters sent via metadata
if meeting_metadata["opencast-add-webcams"].nil?
  meeting_metadata["opencast-add-webcams"] = 'true'
end

# Create metadata file dublincore
dc_data = OcDublincore::parseDcMetadata(meeting_metadata, server: oc_server, user: oc_user, password: oc_password)
dublincoreXML = OcDublincore::createDublincore(dc_data)
BigBlueButton.logger.info( "Dublincore: \n" + dublincoreXML.to_s)

# Create ACLs at path
aclData = OcAcl::parseEpisodeAclMetadata(meeting_metadata, $defaultRolesWithReadPerm, $defaultRolesWithWritePerm)
if (!aclData.nil? && !aclData.empty?)
  File.write(ACL_PATH, OcAcl::createAcl(aclData))
end

# Create series with given seriesId, if such a series does not yet exist
if (createNewSeriesIfItDoesNotYetExist)
  OcAcl::createSeries(meeting_metadata, oc_server, oc_user, oc_password, defaultSeriesRolesWithReadPerm, defaultSeriesRolesWithWritePerm)
end

#
# Create a mediapackage and ingest it
#

BigBlueButton.logger.info( "Upload Recording for [#{meeting_id}]...")

# Create Mediapackage
if !dc_data[:identifier].to_s.empty?
  mediapackage = OcUtil::requestIngestAPI(oc_server, oc_user, oc_password,
    :put, '/ingest/createMediaPackageWithID/' + dc_data[:identifier], DEFAULT_REQUEST_TIMEOUT, {}
  )
else
  mediapackage = OcUtil::requestIngestAPI(oc_server, oc_user, oc_password,
    :get, '/ingest/createMediaPackage', DEFAULT_REQUEST_TIMEOUT, {}
  )
end

# Get mediapackageId for debugging
doc = Nokogiri::XML(mediapackage)
mediapackageId = doc.xpath("/*")[0].attr('id')

# Add Track
if (File.exists?(published_files + '/video/webcams.webm') && meeting_metadata["opencast-add-webcams"] == 'true')
  BigBlueButton.logger.info( "Found presenter video")
  mediapackage = OcUtil::requestIngestAPI(oc_server, oc_user, oc_password,
                  :post, '/ingest/addPartialTrack', DEFAULT_REQUEST_TIMEOUT,
                  { :flavor => 'presenter/source',
                    :mediaPackage => mediapackage,
                    :body => File.open(published_files + '/video/webcams.webm', 'rb') })
end
if (File.exists?(published_files + '/deskshare/deskshare.webm'))
  BigBlueButton.logger.info( "Found presentation video")
  mediapackage = OcUtil::requestIngestAPI(oc_server, oc_user, oc_password,
                  :post, '/ingest/addPartialTrack', DEFAULT_REQUEST_TIMEOUT,
                  { :flavor => 'presentation/source',
                    :mediaPackage => mediapackage,
                    :body => File.open(published_files + '/deskshare/deskshare.webm', 'rb') })
end

# Add dublincore
mediapackage = OcUtil::requestIngestAPI(oc_server, oc_user, oc_password,
                :post, '/ingest/addDCCatalog', DEFAULT_REQUEST_TIMEOUT,
                {:mediaPackage => mediapackage,
                 :dublinCore => dublincoreXML })

# Add ACL if applicable
if (File.file?(ACL_PATH))
  mediapackage = OcUtil::requestIngestAPI(oc_server, oc_user, oc_password,
                  :post, '/ingest/addAttachment', DEFAULT_REQUEST_TIMEOUT,
                  {:mediaPackage => mediapackage,
                  :flavor => "security/xacml+episode",
                  :body => File.open(ACL_PATH, 'rb') })
else
  BigBlueButton.logger.info( "No ACL found, skipping adding ACL.")
end

# Ingest and start workflow
BigBlueButton.logger.info( "Uploading...")
response = OcUtil::requestIngestAPI(oc_server, oc_user, oc_password,
                :post, '/ingest/ingest/' + oc_workflow, START_WORKFLOW_REQUEST_TIMEOUT,
                { :mediaPackage => mediapackage },
                "LOG ERROR Aborting ingest with BBB id #{meeting_id} and OC id #{mediapackageId}")
BigBlueButton.logger.info( "Upload for [#{meeting_id}] ends")

# Remove temporary files
if (File.file?(ACL_PATH))
  File.delete(ACL_PATH)
end

exit 0
