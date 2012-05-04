class GenericFile < ActiveFedora::Base
  include Hydra::ModelMixins::CommonMetadata
  include Hydra::ModelMethods
  include PSU::Noid
  include Dil::RightsMetadata

  has_metadata :name => "characterization", :type => FitsDatastream
  has_metadata :name => "descMetadata", :type => GenericFileRdfDatastream
  has_file_datastream :type => FileContentDatastream
  has_file_datastream :name => "thumbnail", :type => FileContentDatastream

  belongs_to :batch, :property => :is_part_of

  delegate :related_url, :to => :descMetadata
  delegate :based_near, :to => :descMetadata
  delegate :part_of, :to => :descMetadata
  delegate :contributor, :to => :descMetadata
  delegate :creator, :to => :descMetadata
  delegate :title, :to => :descMetadata
  delegate :tag, :to => :descMetadata
  delegate :description, :to => :descMetadata
  delegate :publisher, :to => :descMetadata
  delegate :date_created, :to => :descMetadata
  delegate :date_uploaded, :to => :descMetadata
  delegate :date_modified, :to => :descMetadata
  delegate :subject, :to => :descMetadata
  delegate :language, :to => :descMetadata
  delegate :date, :to => :descMetadata
  delegate :rights, :to => :descMetadata
  delegate :resource_type, :to => :descMetadata
  delegate :format, :to => :descMetadata
  delegate :identifier, :to => :descMetadata
  delegate :format_label, :to => :characterization
  delegate :mime_type, :to => :characterization, :unique=>true
  delegate :file_size, :to => :characterization
  delegate :last_modified, :to => :characterization
  delegate :filename, :to => :characterization
  delegate :original_checksum, :to => :characterization
  delegate :rights_basis, :to => :characterization
  delegate :copyright_basis, :to => :characterization
  delegate :copyright_note, :to => :characterization
  delegate :well_formed, :to => :characterization
  delegate :valid, :to => :characterization
  delegate :status_message, :to => :characterization
  delegate :file_title, :to => :characterization
  delegate :file_author, :to => :characterization
  delegate :page_count, :to => :characterization
  delegate :file_language, :to => :characterization
  delegate :word_count, :to => :characterization
  delegate :character_count, :to => :characterization
  delegate :paragraph_count, :to => :characterization
  delegate :line_count, :to => :characterization
  delegate :table_count, :to => :characterization
  delegate :graphics_count, :to => :characterization
  delegate :byte_order, :to => :characterization
  delegate :compression, :to => :characterization
  delegate :width, :to => :characterization
  delegate :height, :to => :characterization
  delegate :color_space, :to => :characterization
  delegate :profile_name, :to => :characterization
  delegate :profile_version, :to => :characterization
  delegate :orientation, :to => :characterization
  delegate :color_map, :to => :characterization
  delegate :image_producer, :to => :characterization
  delegate :capture_device, :to => :characterization
  delegate :scanning_software, :to => :characterization
  delegate :exif_version, :to => :characterization
  delegate :gps_timestamp, :to => :characterization
  delegate :latitude, :to => :characterization
  delegate :longitude, :to => :characterization
  delegate :character_set, :to => :characterization
  delegate :markup_basis, :to => :characterization
  delegate :markup_language, :to => :characterization
  delegate :duration, :to => :characterization
  delegate :bit_depth, :to => :characterization
  delegate :sample_rate, :to => :characterization
  delegate :channels, :to => :characterization
  delegate :data_format, :to => :characterization
  delegate :offset, :to => :characterization

  around_save :characterize_if_changed
  after_initialize :add_zip_behaviors


  def add_zip_behaviors
    self.extend PSU::ZipBehavior if zip_file?
  end

  ## Updates those permissions that are provided to it. Does not replace any permissions unless they are provided
  def permissions=(params)
    perm_hash = permission_hash
    perm_hash['person'][params[:new_user_name]] = params[:new_user_permission] if params[:new_user_name].present?
    perm_hash['group'][params[:new_group_name]] = params[:new_group_permission] if params[:new_group_name].present?

    params[:user].each { |name, access| perm_hash['person'][name] = access} if params[:user]
    params[:group].each { |name, access| perm_hash['group'][name] = access} if params[:group]
    
    rightsMetadata.update_permissions(perm_hash)
  end

  def characterize_if_changed
     content_changed = self.content.changed?
     yield
     Delayed::Job.enqueue(CharacterizeJob.new(self.pid)) if content_changed
  end

  ## Extract the metadata from the content datastream and record it in the characterization datastream
  def characterize
    self.characterization.content = self.content.extract_metadata
    self.append_metadata
    self.filename = self.label
    save unless self.new_object?
  end

  def related_files
    self.batch.generic_files.reject { |gf| gf.pid == self.pid }
  end

  # Create thumbnail requires that the characterization has already been run (so mime_type, width and height is available)
  # and that the object is already has a pid set
  def create_thumbnail
    return if self.content.content.nil?
    image_path = write_payload_to_tempfile

    if ["application/pdf"].include? self.mime_type.first
      create_pdf_thumnail(image_path)
    elsif ["image/png","image/jpeg", "image/gif"].include? self.mime_type.first
      create_image_thumnail(image_path)
    end
    # if we can figure out how to do video
    #elsif ["video/mpeg", "video/mp4"].include? self.mime_type
  end

  def write_payload_to_tempfile
    f = Tempfile.new("#{self.pid}-#{self.content.dsVersionID}")

    f.binmode
    if self.content.content.respond_to? :read
      f.write(self.content.content.read)
    else
      f.write(self.content.content)
    end 
    f.close
    f.path
  end

  def create_pdf_thumnail(image_path)
      pdf = Magick::ImageList.new(image_path)[0]
      thumb = pdf.scale(45, 60)
      tmp_thumb = File.new("/tmp/#{self.pid}-#{self.content.dsVersionID}-thumb.png", "w+")
      thumb.write tmp_thumb.path 
      self.add_file_datastream(tmp_thumb, :dsid=>'thumbnail')
      self.save
      File.unlink(tmp_thumb.path)
  end

  def create_image_thumnail(image_path)
    img = Magick::ImageList.new(image_path)

    # horizontal img
    height = self.height.first.to_i
    width = self.width.first.to_i
    if width > height
      if width > 50 and height > 35 
        thumb = img.scale(50, 35)
      else
        thumb = img.scale(width, height)
      end
    # vertical img
    else
      if width > 45 and height > 60 
        thumb = img.scale(45, 60)
      else
        thumb = img.scale(width, height)
      end
    end
    tmp_thumb = File.new("/tmp/#{self.pid}-#{self.content.dsVersionID}-thumb.png", "w+")
    thumb.write tmp_thumb.path 
    self.add_file_datastream(tmp_thumb, :dsid=>'thumbnail')
    logger.debug "Has the content before saving? #{self.content.changed?}"
    self.save
    File.unlink(tmp_thumb.path)
  end

  def zip_file?
    mime_type == 'application/zip'
  end

  def append_metadata
    terms = self.characterization_terms
    ScholarSphere::Application.config.fits_to_desc_mapping.each_pair do |k, v|
      if terms.has_key?(k)
        proxy_term = self.send(v)
        if terms[k].is_a? Array
          terms[k].each do |term_value|
            proxy_term << term_value unless proxy_term.include?(term_value)
          end
        else
          proxy_term << terms[k]
        end
      end
    end
  end
  
  def to_solr(solr_doc={})
    super(solr_doc)
    solr_doc["label_t"] = self.label
    solr_doc["noid_s"] = noid
    return solr_doc
  end
  
  def label=(new_label)
    @inner_object.label = new_label
    if self.title.empty?
      self.title = new_label
    end
  end

  def to_jq_upload
    return {
      "name" => self.title,
      "size" => self.file_size,
      "url" => "/files/#{noid}",
      "thumbnail_url" => self.pid,
      "delete_url" => "deleteme", # generic_file_path(:id => id),
      "delete_type" => "DELETE" 
    }
  end

  def get_terms
    terms = []
    self.descMetadata.class.config[:predicate_mapping].each do |uri, mappings|
      new_terms = mappings.keys.map(&:to_s).select do |term|
        term.start_with? "generic_file__" and !['solrtype', 'solrbehaviors'].include? term.split('__').last
      end
      terms.concat(new_terms)
    end 
    terms
  end

  def characterization_terms
    h = {}
    self.characterization.class.terminology.terms.each_pair do |k, v|
      next unless v.respond_to? :proxied_term
      term = v.proxied_term
      begin
        value = self.send(term.name)
        h[term.name] = value unless value.empty?
      rescue NoMethodError
        next
      end
    end
    h
  end

  def logs(dsid)
    ChecksumAuditLog.where(:dsid=>dsid, :pid=>self.pid).order('created_at desc, id desc')
  end

  def audit!
    audit(true)
  end

  def audit_stat
      logs = audit(true)
      logger.info "*****"
      logger.info logs.inspect
      logger.info "*****"
      audit_results = logs.collect { |result| result["pass"] }
      logger.info "!*****"
      logger.info audit_results.inspect
      logger.info "!*****"
      result =audit_results.reduce(true) { |sum, value| sum && value }
      result
  end

  def audit(force = false)
    logs = []
    self.per_version do |ver| 
      logs << GenericFile.audit(ver, force)
    end
    logs
  end

  def per_version(&block)
    self.datastreams.each do |dsid, ds|
      ds.versions.each do |ver|
        block.call(ver)
      end
    end
  end

  def GenericFile.audit!(version)
    GenericFile.audit(version, true)
  end

  def GenericFile.audit(version, force = false)
    logger.debug "***AUDIT*** log for #{version.inspect}"
    latest_audit = self.find(version.pid).logs(version.dsid).first
    unless force
      return unless GenericFile.needs_audit?(version, latest_audit)
    end
    if version.dsChecksumValid
      logger.info "***AUDIT*** Audit passed for #{version.pid} #{version.versionID}"
      passing = true
      ChecksumAuditLog.prune_history(version)
    else
      logger.warn "***AUDIT*** Audit failed for #{version.pid} #{version.versionID}"
      passing = false
    end
    ChecksumAuditLog.create!(:pass=>passing, :pid=>version.pid,
                             :dsid=>version.dsid, :version=>version.versionID)
  end

  def GenericFile.needs_audit?(version, latest_audit)
    if latest_audit and latest_audit.updated_at
      logger.debug "***AUDIT*** last audit = #{latest_audit.updated_at.to_date}"
      days_since_last_audit = (DateTime.now - latest_audit.updated_at.to_date).to_i
      logger.debug "***AUDIT*** days since last audit: #{days_since_last_audit}"
      if days_since_last_audit < Rails.application.config.max_days_between_audits
        logger.debug "***AUDIT*** No audit needed for #{version.pid} #{version.versionID} (#{latest_audit.updated_at})"
        return false
      end
    else
      logger.warn "***AUDIT*** problem with audit log!"
    end
    logger.info "***AUDIT*** Audit needed for #{version.pid} #{version.versionID}"
    true
  end

  def GenericFile.audit_everything(force = false)
    GenericFile.find(:all).each do |gf|
      gf.per_version do |ver|
        GenericFile.audit(ver, force)
      end
    end
  end

  def GenericFile.audit_everything!
    GenericFile.audit_everything(true)
  end

  private 

  def permission_hash
    old_perms = self.permissions
    user_perms =  {}
    old_perms.select{|r| r[:type] == 'user'}.each do |r|
      user_perms[r[:name]] = r[:access]
    end
    user_perms
    group_perms =  {}
    old_perms.select{|r| r[:type] == 'group'}.each do |r|
      group_perms[r[:name]] = r[:access]
    end
    {'person'=>user_perms, 'group'=>group_perms}
  end
end
