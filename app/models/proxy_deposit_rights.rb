class ProxyDepositRights < ApplicationRecord
  belongs_to :grantor, class_name: "User"
  belongs_to :grantee, class_name: "User"
end
