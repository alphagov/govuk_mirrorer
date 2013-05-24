require 'spec_helper'

describe GovukMirrorer::Configurer do

  describe "Setting site_root" do
    it "should fail if site_root is not set" do
      lambda do
        GovukMirrorer::Configurer.run([])
      end.should raise_error(GovukMirrorer::Configurer::NoRootUrlSpecifiedError)

      ENV.stub(:[]).with('MIRRORER_SITE_ROOT').and_return("")
      lambda do
        GovukMirrorer::Configurer.run([])
      end.should raise_error(GovukMirrorer::Configurer::NoRootUrlSpecifiedError)
    end

    it "should take a site-root option on the commandline" do
      GovukMirrorer::Configurer.run(%w[--site-root sausage]).should include(:site_root => "sausage" )
    end

    it "should read the site root from an ENV variable" do
      ENV.stub(:[]).with('MIRRORER_SITE_ROOT').and_return("sausage")
      GovukMirrorer::Configurer.run([]).should include(:site_root => "sausage" )
    end

    it "should take the commandline option in preference to the ENV variable if both are specified" do
      ENV.stub(:[]).with('MIRRORER_SITE_ROOT').and_return("sausage")
      GovukMirrorer::Configurer.run(%w[--site-root mash]).should include(:site_root => "mash" )
    end
  end
end
