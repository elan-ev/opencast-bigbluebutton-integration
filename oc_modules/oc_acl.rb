require_relative 'oc_util'
require_relative 'oc_dublincore'

require 'nokogiri'        #XML-Parser
require 'json'

module OcAcl

  def self.private_module_function(name)   #:nodoc:
    module_function name
    private_class_method name
  end

  #
  # Returns the metadata tags defined for user access list
  #
  # return: hash
  #
  def getAclMetadataDefinition()
    return {:readRoles => "opencast-acl-read-roles",
            :writeRoles => "opencast-acl-write-roles",
            :userIds => "opencast-acl-user-id"}
  end
  private_module_function :getAclMetadataDefinition

  #
  # Returns the metadata tags defined for series access list
  #
  # return: hash
  #
  def getSeriesAclMetadataDefinition()
    return {:readRoles => "opencast-series-acl-read-roles",
            :writeRoles => "opencast-series-acl-write-roles",
            :userIds => "opencast-series-acl-user-id"}
  end
  private_module_function :getSeriesAclMetadataDefinition

  #
  # Parses acl-relevant information from the metadata
  #
  # metadata: hash (string => string)
  # defaultReadRoles: string with comma seperated values, roles that should ALWAYS have read access
  # defaultWriteRoles: string with comma seperated values, roles that should ALWAYS have write access
  #
  # return array of hash (symbol => string, symbol => string)
  #
  def parseAclMetadata(metadata, acl_metadata_definition, defaultReadRoles = "", defaultWriteRoles = "")
    # Cast keys to lowercase
    metadata = OcUtil::keysLowerCase(metadata)

    acl_data = []

    # Read from global, configured-by-user variable
    defaultReadRoles.to_s.split(",").each do |role|
      acl_data.push( { :user => role, :permission => "read" } )
    end
    defaultWriteRoles.to_s.split(",").each do |role|
      acl_data.push( { :user => role, :permission => "write" } )
    end

    # Read from Metadata
    metadata[acl_metadata_definition[:readRoles]].to_s.split(",").each do |role|
      acl_data.push( { :user => role, :permission => "read" } )
    end
    metadata[acl_metadata_definition[:writeRoles]].to_s.split(",").each do |role|
      acl_data.push( { :user => role, :permission => "write" } )
    end

    metadata[acl_metadata_definition[:userIds]].to_s.split(",").each do |userId|
      acl_data.push( { :user => "ROLE_USER_#{userId}", :permission => "read" } )
      acl_data.push( { :user => "ROLE_USER_#{userId}", :permission => "write" } )
    end

    return acl_data
  end
  private_module_function :parseAclMetadata

  def parseEpisodeAclMetadata(metadata, defaultReadRoles = "", defaultWriteRoles = "")
    return parseAclMetadata(metadata, getAclMetadataDefinition(), defaultReadRoles, defaultWriteRoles)
  end
  module_function :parseEpisodeAclMetadata


  def parseSeriesAclMetadata(metadata, defaultReadRoles = "", defaultWriteRoles = "")
    return parseAclMetadata(metadata, getSeriesAclMetadataDefinition(), defaultReadRoles, defaultWriteRoles)
  end
  module_function :parseSeriesAclMetadata

  #
  # Creates a xml using the given role information
  #
  # roles: array of hash (symbol => string, symbol => string), containing user role and permission
  #
  # returns: string, the xml
  #
  def createAcl(roles)
    header = Nokogiri::XML('<?xml version = "1.0" encoding = "UTF-8" standalone ="yes"?>')
    builder = Nokogiri::XML::Builder.with(header) do |xml|
      xml.Policy('PolicyId' => 'mediapackage-1',
      'RuleCombiningAlgId' => 'urn:oasis:names:tc:xacml:1.0:rule-combining-algorithm:permit-overrides',
      'Version' => '2.0',
      'xmlns' => 'urn:oasis:names:tc:xacml:2.0:policy:schema:os') {
        roles.each do |role|
          xml.Rule('RuleId' => "#{role[:user]}_#{role[:permission]}_Permit", 'Effect' => 'Permit') {
            xml.Target {
              xml.Actions {
                xml.Action {
                  xml.ActionMatch('MatchId' => 'urn:oasis:names:tc:xacml:1.0:function:string-equal') {
                    xml.AttributeValue('DataType' => 'http://www.w3.org/2001/XMLSchema#string') { xml.text(role[:permission]) }
                    xml.ActionAttributeDesignator('AttributeId' => 'urn:oasis:names:tc:xacml:1.0:action:action-id',
                    'DataType' => 'http://www.w3.org/2001/XMLSchema#string')
                  }
                }
              }
            }
            xml.Condition{
              xml.Apply('FunctionId' => 'urn:oasis:names:tc:xacml:1.0:function:string-is-in') {
                xml.AttributeValue('DataType' => 'http://www.w3.org/2001/XMLSchema#string') { xml.text(role[:user]) }
                xml.SubjectAttributeDesignator('AttributeId' => 'urn:oasis:names:tc:xacml:2.0:subject:role',
                'DataType' => 'http://www.w3.org/2001/XMLSchema#string')
              }
            }
          }
        end
      }
    end

    return builder.to_xml
  end
  module_function :createAcl

  #
  # Creates a xml using the given role information
  #
  # roles: array of hash (symbol => string, symbol => string), containing user role and permission
  #
  # returns: string, the xml
  #
  def createSeriesAcl(roles)
    header = Nokogiri::XML('<?xml version = "1.0" encoding = "UTF-8" standalone ="yes"?>')
    builder = Nokogiri::XML::Builder.with(header) do |xml|
      xml.acl('xmlns' => 'http://org.opencastproject.security') {
        roles.each do |role|
          xml.ace {
            xml.action { xml.text(role[:permission]) }
            xml.allow { xml.text('true') }
            xml.role { xml.text(role[:user]) }
          }
        end
      }
    end

    return builder.to_xml
  end
  private_module_function :createSeriesAcl

  #
  # Extends a series ACL with given roles, if those roles are not already part of the ACL
  #
  # xml: A parsable xml string
  # roles: array of hash (symbol => string, symbol => string), containing user role and permission
  #
  # returns:
  #
  def updateSeriesAcl(xml, roles)

    doc = Nokogiri::XML(xml)
    newNodeSet = Nokogiri::XML::NodeSet.new(doc)

    roles.each do |role|
      newNode = OcUtil::nokogiriNodeCreator(doc, "ace", "")
      newNode << OcUtil::nokogiriNodeCreator(doc, "action", role[:permission])
      newNode <<  OcUtil::nokogiriNodeCreator(doc, "allow", 'true')
      newNode <<  OcUtil::nokogiriNodeCreator(doc, "role", role[:user])

      # Avoid adding duplicate nodes
      nodeAlreadyExists = false
      doc.xpath("//x:ace", "x" => "http://org.opencastproject.security").each do |oldNode|
        if OcUtil::sameNodes?(oldNode, newNode)
          nodeAlreadyExists = true
          break
        end
      end

      if (!nodeAlreadyExists)
        newNodeSet << newNode
      end
    end

    doc.root << newNodeSet

    return doc.to_xml
  end
  private_module_function :updateSeriesAcl

  #
  # Will create a new series with the given Id, if such a series does not yet exist
  # Else will try to update the ACL of the series
  #
  # createSeriesId: string, the UID for the new series
  #
  def createSeries(meeting_metadata, oc_server, oc_user, oc_password, defaultSeriesRolesWithReadPerm="", defaultSeriesRolesWithWritePerm="")
    if !oc_server || !oc_user || !oc_password
      BigBlueButton.logger.warn("OC_ACL: Cannot create or update series: No credentials given.")
      return nil
    end

    # Cast keys to lowercase
    meeting_metadata = OcUtil::keysLowerCase(meeting_metadata)

    createSeriesId = meeting_metadata["opencast-dc-ispartof"]
    if (createSeriesId.to_s.empty?)
      BigBlueButton.logger.warn("OC_ACL: Cannot create or update series: Metadata does not contain a seriesId.")
      return
    end

    BigBlueButton.logger.info("OC_ACL: Attempting to create a new series...")

    # Acquire information about all series
    seriesFromOc = []
    begin
      seriesFromOc = RestClient::Request.new(
        :method => :get,
        :url => oc_server + '/series/allSeriesIdTitle.json',
        :user => oc_user,
        :password => oc_password,
        :payload => {}
      ).execute
    rescue RestClient::Exception => e
      "LOG WARN Could not acquire information about series, Exception #{e}"
      return
    end

    # Check if a series with the given identifier does already exist
    seriesExists = false
    begin
      seriesFromOc = JSON.parse(seriesFromOc)
      seriesFromOc["series"].each do |serie|
        BigBlueButton.logger.info("OC_ACL: Found series: " + serie["identifier"].to_s)
        if (serie["identifier"].to_s === createSeriesId.to_s)
          seriesExists = true
          BigBlueButton.logger.info("OC_ACL: Series already exists")
          break
        end
      end
    rescue JSON::ParserError  => e
      BigBlueButton.logger.warn("OC_ACL: Could not parse series JSON, Exception #{e}")
    end

    # Create Series
    if (!seriesExists)
      BigBlueButton.logger.info("OC_ACL: Create a new series with ID " + createSeriesId)
      # Create Series-DC
      seriesDcData = OcDublincore::parseSeriesDcMetadata(meeting_metadata)
      seriesDublincore = OcDublincore::createDublincore(seriesDcData)
      # Create Series-ACL
      seriesAcl = createSeriesAcl(parseSeriesAclMetadata(meeting_metadata, defaultSeriesRolesWithReadPerm,
                  defaultSeriesRolesWithWritePerm))
      BigBlueButton.logger.info("OC_ACL: seriesAcl: " + seriesAcl.to_s)

      begin
        response = RestClient::Request.new(
          :method => :post,
          :url => oc_server + '/series/',
          :user => oc_user,
          :password => oc_password,
          :payload => { :series => seriesDublincore,
                        :acl => seriesAcl,
                        :override => false}
        ).execute
      rescue RestClient::Exception => e
        "LOG WARN Something went wrong during series creation, Exception #{e}"
        return
      end

    # Update Series ACL
    else
      BigBlueButton.logger.info("OC_ACL: Updating series ACL...")
      # seriesAcl = requestIngestAPI(:get, '/series/' + createSeriesId + '/acl.xml', DEFAULT_REQUEST_TIMEOUT, {})
      seriesAcl = []
      begin
        seriesAcl = RestClient::Request.new(
          :method => :get,
          :url => oc_server + '/series/' + createSeriesId + '/acl.xml',
          :user => oc_user,
          :password => oc_password,
          :payload => { }
        ).execute
      rescue RestClient::Exception => e
        "LOG WARN OC_ACL: Something went wrong during series update, Exception #{e}"
        return
      end
      roles = parseSeriesAclMetadata(meeting_metadata, defaultSeriesRolesWithReadPerm, defaultSeriesRolesWithWritePerm)

      if (roles.length > 0)
        updatedSeriesAcl = updateSeriesAcl(seriesAcl, roles)
        begin
          response = RestClient::Request.new(
            :method => :post,
            :url => oc_server + '/series/' + createSeriesId + '/accesscontrol',
            :user => oc_user,
            :password => oc_password,
            :payload => { :acl => updatedSeriesAcl,
                          :override => false }
          ).execute
        rescue RestClient::Exception => e
          "LOG WARN OC_ACL: Something went wrong during series update, Exception #{e}"
          return
        end
        BigBlueButton.logger.info("OC_ACL: Updated series ACL")
      else
        BigBlueButton.logger.info("OC_ACL: Nothing to update ACL with")
      end
    end
  end
  module_function :createSeries

end