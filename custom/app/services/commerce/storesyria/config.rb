# The installation switch for the Store Syria provider.
#
# Orthogonal to the account-level `lynomia_commerce` plan feature, exactly as Zid's and Salla's
# are: this says the INSTALLATION offers the provider at all, the feature flag says a given
# account may use it. Both must be true.
module Commerce::Storesyria::Config
  module_function

  def enabled? = GlobalConfigService.load('STORESYRIA_ENABLED', false).to_s == 'true'
end
