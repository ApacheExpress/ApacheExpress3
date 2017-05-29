# GNUmakefile

PACKAGE_DIR=.

include $(PACKAGE_DIR)/xcconfig/config.make

MODULES = ApacheExpress3

ifeq ($(HAVE_SPM),yes)

all :
	$(SWIFT_BUILD_TOOL)

clean :
	$(SWIFT_CLEAN_TOOL)

distclean : clean
	rm -rf .build Packages

tests : all
	$(SWIFT_TEST_TOOL)
	
update:
	swift package update

else

MODULE_LIBS = \
  $(addsuffix $(SHARED_LIBRARY_SUFFIX),$(addprefix $(SHARED_LIBRARY_PREFIX),$(MODULES)))
MODULE_BUILD_RESULTS = $(addprefix $(SWIFT_BUILD_DIR)/,$(MODULE_LIBS))

all :
	@$(MAKE) -C Sources/ApacheExpress3 all

clean :
	rm -rf .build

distclean : clean

update:

endif
