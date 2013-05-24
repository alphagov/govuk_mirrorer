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

  describe "setting the request interval" do
    before :each do
      ENV.stub(:[]).with('MIRRORER_SITE_ROOT').and_return("sausage")
    end

    it "should allow setting the request interval" do
      GovukMirrorer::Configurer.run(%w[--request-interval 0.6]).should include(:request_interval => 0.6)
    end

    it "should default to 0.1" do
      GovukMirrorer::Configurer.run([]).should include(:request_interval => 0.1)
    end
  end


  describe "setting up logging" do
    before :each do
      ENV.stub(:[]).with('MIRRORER_SITE_ROOT').and_return("sausage")
    end

    it "should allow specifying a logfile" do
      GovukMirrorer::Configurer.run(%w[--logfile /foo/bar]).should include(:log_file => "/foo/bar")
    end

    it "should allow logging to syslog with default facility of local3" do
      GovukMirrorer::Configurer.run(%w[--syslog]).should include(:syslog => "local3")
    end

    it "should allow logging to syslog overriding the default facility" do
      GovukMirrorer::Configurer.run(%w[--syslog local5]).should include(:syslog => "local5")
    end
  end
end
