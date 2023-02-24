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

#
# Initialize logger
logger = Logger.new("/var/log/bigbluebutton/post_publish.log", 'weekly' )
logger.level = Logger::INFO
BigBlueButton.logger = logger

### Load configuration begin

# Define default config values
config_defaults = {
  defaultRoles: {
    readPerm: "",
    writePerm: "",
    seriesReadPerm: "",
    seriesWritePerm: "",
  },
  miscellaneous: {
    createNewSeriesIfItDoesNotYetExist: false,
  },
}

# Parse configuration from config file
$config = TomlRB.load_file(__dir__ + '/post_publish_config.toml', symbolize_keys: true)
BigBlueButton.logger.info("Opencast Server: " + $config.dig(:opencast, :server))

# Check for essential values
$config[:opencast].each do |oc_key, oc_value|
  if oc_value.to_s.empty?
    BigBlueButton.logger.error(" The config key " + oc_key + "is not set. Aborting...")
    exit 1
  end
end

# Set defaults in case they were not configured
$config = config_defaults.merge($config)


#
# Parse cmd args from BBB

opts = Optimist::options do
 opt :meeting_id, "Meeting id to archive", :type => String
 opt :file_type, "File type", :type => String
end
meeting_id = opts[:meeting_id]

published_files = "/var/bigbluebutton/published/presentation/#{meeting_id}"
meeting_metadata = BigBlueButton::Events.get_meeting_metadata("/var/bigbluebutton/recording/raw/#{meeting_id}/events.xml")

# Variables
DEFAULT_REQUEST_TIMEOUT = 10                                  # Http request timeout in seconds
START_WORKFLOW_REQUEST_TIMEOUT = 6000                         # Specific timeout; Opencast runs MediaInspector on every file, which can take quite a while
ACL_PATH = File.join(published_files, "acl.xml")

BigBlueButton.logger.info("Prepare Metadata for [#{meeting_id}]...")

# Check parameters sent via metadata
if meeting_metadata["opencast-add-webcams"].nil?
  meeting_metadata["opencast-add-webcams"] = 'true'
end

# Create metadata file dublincore
dc_data = OcDublincore::parseDcMetadata(meeting_metadata, server: $config.dig(:opencast, :server), user: $config.dig(:opencast, :user), password: $config.dig(:opencast, :password))
dublincoreXML = OcDublincore::createDublincore(dc_data)
BigBlueButton.logger.info("Dublincore: \n" + dublincoreXML.to_s)

# Create ACLs at path
aclData = OcAcl::parseEpisodeAclMetadata(meeting_metadata, $config.dig(:defaultRoles, :readPerm), $config.dig(:defaultRoles, :writePerm))
if (!aclData.nil? && !aclData.empty?)
  File.write(ACL_PATH, OcAcl::createAcl(aclData))
end

# Create series with given seriesId, if such a series does not yet exist
if ($config.dig(:miscellaneous, :createNewSeriesIfItDoesNotYetExist))
  OcAcl::createSeries(meeting_metadata, $config.dig(:opencast, :server), $config.dig(:opencast, :user), $config.dig(:opencast, :password), $config.dig(:defaultRoles, :seriesReadPerm), $config.dig(:defaultRoles, :seriesWritePerm))
end

#
# Create a mediapackage and ingest it
#

BigBlueButton.logger.info("Upload Recording for [#{meeting_id}]...")

# Create Mediapackage
if !dc_data[:identifier].to_s.empty?
  mediapackage = OcUtil::requestIngestAPI($config.dig(:opencast, :server), $config.dig(:opencast, :user), $config.dig(:opencast, :password),
    :put, '/ingest/createMediaPackageWithID/' + dc_data[:identifier], DEFAULT_REQUEST_TIMEOUT, {}
  )
else
  mediapackage = OcUtil::requestIngestAPI($config.dig(:opencast, :server), $config.dig(:opencast, :user), $config.dig(:opencast, :password),
    :get, '/ingest/createMediaPackage', DEFAULT_REQUEST_TIMEOUT, {}
  )
end

# Get mediapackageId for debugging
doc = Nokogiri::XML(mediapackage)
mediapackageId = doc.xpath("/*")[0].attr('id')

# Add Track
if (File.exists?(published_files + '/video/webcams.webm') && meeting_metadata["opencast-add-webcams"] == 'true')
  BigBlueButton.logger.info("Found presenter video")
  mediapackage = OcUtil::requestIngestAPI($config.dig(:opencast, :server), $config.dig(:opencast, :user), $config.dig(:opencast, :password),
                  :post, '/ingest/addPartialTrack', DEFAULT_REQUEST_TIMEOUT,
                  { :flavor => 'presenter/source',
                    :mediaPackage => mediapackage,
                    :body => File.open(published_files + '/video/webcams.webm', 'rb') })
end
if (File.exists?(published_files + '/deskshare/deskshare.webm'))
  BigBlueButton.logger.info("Found presentation video")
  mediapackage = OcUtil::requestIngestAPI($config.dig(:opencast, :server), $config.dig(:opencast, :user), $config.dig(:opencast, :password),
                  :post, '/ingest/addPartialTrack', DEFAULT_REQUEST_TIMEOUT,
                  { :flavor => 'presentation/source',
                    :mediaPackage => mediapackage,
                    :body => File.open(published_files + '/deskshare/deskshare.webm', 'rb') })
end

# Add dublincore
mediapackage = OcUtil::requestIngestAPI($config.dig(:opencast, :server), $config.dig(:opencast, :user), $config.dig(:opencast, :password),
                :post, '/ingest/addDCCatalog', DEFAULT_REQUEST_TIMEOUT,
                {:mediaPackage => mediapackage,
                 :dublinCore => dublincoreXML })

# Add ACL if applicable
if (File.file?(ACL_PATH))
  mediapackage = OcUtil::requestIngestAPI($config.dig(:opencast, :server), $config.dig(:opencast, :user), $config.dig(:opencast, :password),
                  :post, '/ingest/addAttachment', DEFAULT_REQUEST_TIMEOUT,
                  {:mediaPackage => mediapackage,
                  :flavor => "security/xacml+episode",
                  :body => File.open(ACL_PATH, 'rb') })
else
  BigBlueButton.logger.info("No ACL found, skipping adding ACL.")
end

# Ingest and start workflow
BigBlueButton.logger.info("Uploading...")
response = OcUtil::requestIngestAPI($config.dig(:opencast, :server), $config.dig(:opencast, :user), $config.dig(:opencast, :password),
                :post, '/ingest/ingest/' + $config.dig(:opencast, :workflow), START_WORKFLOW_REQUEST_TIMEOUT,
                { :mediaPackage => mediapackage },
                "LOG ERROR Aborting ingest with BBB id #{meeting_id} and OC id #{mediapackageId}")
BigBlueButton.logger.info("Upload for [#{meeting_id}] ends")

# Remove temporary files
if (File.file?(ACL_PATH))
  File.delete(ACL_PATH)
end

exit 0
