require 'httparty'
load './models/project.rb'

class AzureProject < Project
  after_initialize :construct_metadata

  def tenant_id
    @metadata['tenant_id']
  end

  def azure_client_id
    @metadata['client_id']
  end

  def subscription_id
    @metadata['subscription_id']
  end

  def client_secret
    @metadata['client_secret']
  end

  def bearer_token
    @metadata['bearer_token']
  end

  def bearer_expiry
    @metadata['bearer_expiry']
  end

  def update_bearer_token
    response = HTTParty.post(
      "https://login.microsoftonline.com/#{self.tenant_id}/oauth2/token",
      body: URI.encode_www_form(
        client_id: self.azure_client_id,
        client_secret: self.client_secret,
        resource: 'https://management.azure.com',
        grant_type: 'client_credentials',
      ),
      headers: {
        'Accept' => 'application/json'
      }
    )

    if response.success?
      db = SQLite3::Database.open 'db/cost_tracker.sqlite3'
      body = JSON.parse(response.body)
      @metadata['bearer_token'] = body['access_token']
      @metadata['bearer_expiry'] = body['expires_on']
      db.execute "UPDATE projects
                  SET metadata = '#{@metadata.to_json}'
                  WHERE id = #{self.id}"
    else
      raise RuntimeError, "Error obtaining new authorization token. Error code #{response.code}."
    end
  end

  private

  def construct_metadata
    @metadata = JSON.parse(self.metadata)
  end

end
