use strict;
use warnings;

package Grace::Toolchain::Xcode;

use parent 'Grace::Toolchain';

use Version::Compare;
use File::Spec;
use Carp;
use Data::Dumper;

use Grace::Toolset;
use Grace::Host;
use Grace::Util;

my  @_find_apps;
my  @_find_vers;
my  @_find_plat;
my  @_find_sdks;
my  @_find_tchn;
my  @_find_tool;

our %_lang_pref;
our %_util_pref;
our %_func_tool;
our %_tool_func;
our %_auto_conf;
our $_dflt_conf;

BEGIN {
    # Match language functionality with preferred provider tool.
    %_lang_pref = (
        #--- compiler utilities ---
        'cpp'      => 'cpp',
        'asm'      => 'as',
        'asm-cpp'  => 'clang',
        'c'        => 'clang',
        'c89'      => 'c89',
        'c99'      => 'c99',
        'c++'      => 'clang++',
        'objc'     => 'clang',
        'objc++'   => 'clang',
        'swift'    => 'swiftc',
    );
    
    # Match utility functionality with preferred provider tool.
    %_util_pref = (
        #--- parser utilities ---
        'lex'      => 'flex',
        'flex'     => 'flex',
        'flex++'   => 'flex++',
        'yacc'     => 'bison',
        'm4'       => 'gm4',
        'bison'    => 'bison',
        'indent'   => 'indent',
        #--- objfile functions ---
        'strip'    => 'strip',
        'nm'       => 'nm',
        'strings'  => 'strings',
        'size'     => 'size',
        #--- linker functions ---
        'linkobj'  => 'ld',
#        'linklib'  => [ 'ar', 'ranlib', ],
        'linklib'  => 'libtool',
        'linkdll'  => 'libtool',
        'linkexe'  => 'clang',
        'linkfat'  => 'lipo',
    );
    
    # Configure tools for use as functionality provider.
    %_func_tool = (
        # C preprocessor.  For C++, see 'cxx'.
        'cpp'      => {
            'cpp'     => {
                'toolopt' => [ ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                },
            },
            'c89'     => {
                'toolopt' => [ '-E', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'C89FLAGS'            => [ ],
                },
            },
            'c99'     => {
                'toolopt' => [ '-E', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'C99FLAGS'            => [ ],
                },
            },
            'clang'   => {
                'toolopt' => [ '-E', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CLANGFLAGS'          => [ ],
                },
            },
            'clang++' => {
                'toolopt' => [ '-E', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CLANGXXFLAGS'        => [ ],
                },
            },
            'cc'      => {
                'toolopt' => [ '-E', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                },
            },
            'c++'     => {
                'toolopt' => [ '-E', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                },
            },
            'gcc'     => {
                'toolopt' => [ '-E', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'GNUCFLAGS'           => [ ],
                },
            },
            'g++'     => {
                'toolopt' => [ '-E', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'GNUCXXFLAGS'         => [ ],
                },
            },
        },
        'asm'      => {
            'as'      => {
                'toolopt' => [ ],
                'optvars' => {
                    'ASFLAGS'             => [ ],
                },
            },
            'clang'   => {
                'toolopt' => [ '-xassembler', ],
                'optvars' => {
                    'ASFLAGS'             => [ ],
                    'CLANGASFLAGS'        => [ ],
                    'CLANGFLAGS'          => [ ],
                },
            },
            'clang++' => {
                'toolopt' => [ '-xassembler', ],
                'optvars' => {
                    'ASFLAGS'             => [ ],
                    'CLANGXXASFLAGS'      => [ ],
                    'CLANGXXFLAGS'        => [ ],
                },
            },
            'cc'      => {
                'toolopt' => [ '-xassembler', ],
                'optvars' => {
                    'ASFLAGS'             => [ ],
                },
            },
            'gcc'     => {
                'toolopt' => [ '-xassembler', ],
                'optvars' => {
                    'ASFLAGS'             => [ ],
                    'GNUCASFLAGS'         => [ ],
                    'GNUCFLAGS'           => [ ],
                },
            },
            'g++'     => {
                'toolopt' => [ '-xassembler', ],
                'optvars' => {
                    'ASFLAGS'             => [ ],
                    'GNUCXXASFLAGS'       => [ ],
                    'GNUCXXFLAGS'         => [ ],
                },
            },
        },
        'asm-cpp'  => {
            'clang'   => {
                'toolopt' => [ '-xassembler-with-cpp', ],
                'optvars' => {
                    'ASFLAGS'             => [ ],
                    'CPPFLAGS'            => [ ],
                    'CLANGASFLAGS'        => [ ],
                    'CLANGFLAGS'          => [ ],
                },
            },
            'clang++' => {
                'toolopt' => [ '-xassembler-with-cpp', ],
                'optvars' => {
                    'ASFLAGS'             => [ ],
                    'CPPFLAGS'            => [ ],
                    'CLANGXXASFLAGS'      => [ ],
                    'CLANGXXFLAGS'        => [ ],
                },
            },
            'cc'      => {
                'toolopt' => [ '-xassembler-with-cpp', ],
                'optvars' => {
                    'ASFLAGS'             => [ ],
                    'CPPFLAGS'            => [ ],
                },
            },
            'gcc'     => {
                'toolopt' => [ '-xassembler-with-cpp', ],
                'optvars' => {
                    'ASFLAGS'             => [ ],
                    'CPPFLAGS'            => [ ],
                    'GNUCASFLAGS'         => [ ],
                    'GNUCFLAGS'           => [ ],
                },
            },
            'g++'     => {
                'toolopt' => [ '-xassembler-with-cpp', ],
                'optvars' => {
                    'ASFLAGS'             => [ ],
                    'CPPFLAGS'            => [ ],
                    'GNUCXXASFLAGS'       => [ ],
                    'GNUCXXFLAGS'         => [ ],
                },
            },
        },
        'c'        => {
            'clang'   => {
                'toolopt' => [ '-xc', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CFLAGS'              => [ ],
                    'CLANGFLAGS'          => [ ],
                },
            },
            'cc'      => {
                'toolopt' => [ '-xc', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CFLAGS'              => [ ],
                },
            },
            'gcc'     => {
                'toolopt' => [ '-xc', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CFLAGS'              => [ ],
                    'GNUCFLAGS'           => [ ],
                },
            },
        },
        'c89'      => {
            'c89'     => {
                'toolopt' => [ ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CFLAGS'              => [ ],
                    'C89FLAGS'            => [ ],
                },
            },
            'clang'   => {
                'toolopt' => [ '-xc', '-std=c89', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CFLAGS'              => [ ],
                    'CLANGFLAGS'          => [ ],
                },
            },
            'cc'      => {
                'toolopt' => [ '-xc', '-std=c89', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CFLAGS'              => [ ],
                },
            },
            'gcc'     => {
                'toolopt' => [ '-xc', '-std=c89', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CFLAGS'              => [ ],
                    'GNUCFLAGS'           => [ ],
                },
            },
        },
        'c99'      => {
            'c99'     => {
                'toolopt' => [ ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CFLAGS'              => [ ],
                    'C99FLAGS'            => [ ],
                },
            },
            'clang'   => {
                'toolopt' => [ '-xc', '-std=c99', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CFLAGS'              => [ ],
                    'CLANGFLAGS'          => [ ],
                },
            },
            'cc'      => {
                'toolopt' => [ '-xc', '-std=c99', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CFLAGS'              => [ ],
                },
            },
            'gcc'     => {
                'toolopt' => [ '-xc', '-std=c99', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CFLAGS'              => [ ],
                    'GNUCFLAGS'           => [ ],
                },
            },
        },
        'c++'      => {
            'clang'   => {
                'toolopt' => [ '-xc++', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CXXFLAGS'            => [ ],
                    'CLANGFLAGS'          => [ ],
                },
            },
            'clang++' => {
                'toolopt' => [ ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CXXFLAGS'            => [ ],
                    'CLANGXXFLAGS'        => [ ],
                },
            },
            'cc'      => {
                'toolopt' => [ '-xc++', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CFLAGS'              => [ ],
                },
            },
            'c++'     => {
                'toolopt' => [ ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CXXFLAGS'            => [ ],
                },
            },
            'gcc'     => {
                'toolopt' => [ '-xc++', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CXXFLAGS'            => [ ],
                    'GNUCFLAGS'           => [ ],
                },
            },
            'g++'     => {
                'toolopt' => [ ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'CXXFLAGS'            => [ ],
                    'GNUCXXFLAGS'         => [ ],
                },
            },
        },
        'objc'     => {
            'clang'   => {
                'toolopt' => [ '-ObjC', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'OBJCFLAGS'           => [ ],
                    'CLANGFLAGS'          => [ ],
                },
            },
            'cc'      => {
                'toolopt' => [ '-ObjC', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'OBJCFLAGS'           => [ ],
                },
            },
            'gcc'     => {
                'toolopt' => [ '-ObjC', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'OBJCFLAGS'           => [ ],
                    'GNUCFLAGS'           => [ ],
                },
            },
        },
        'objc++'   => {
            'clang'   => {
                'toolopt' => [ '-ObjC++', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'OBJCXXFLAGS'         => [ ],
                    'CLANGFLAGS'          => [ ],
                },
            },
            'cc'      => {
                'toolopt' => [ '-ObjC++', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'OBJXXCFLAGS'         => [ ],
                },
            },
            'gcc'     => {
                'toolopt' => [ '-ObjC++', ],
                'optvars' => {
                    'CPPFLAGS'            => [ ],
                    'OBJCXXFLAGS'         => [ ],
                    'GNUCFLAGS'           => [ ],
                },
            },
        },
        'swift'    => {
            'swiftc'  => {
                'toolopt' => [ ],
                'optvars' => {
                    'SWIFTFLAGS'          => [ ],
                },
            },
            'swift'   => {
                'toolopt' => [ ],
                'optvars' => {
                    'SWIFTFLAGS'          => [ ],
                },
            },
        },
        'bison'    => {
            'bison'   => {
                'toolopt' => [ ],
                'optvars' => {
                    'BISONFLAGS'          => [ ],
                },
            },
        },
        'yacc'     => {
            'yacc'    => {
                'toolopt' => [ ],
                'optvars' => {
                    'YACCFLAGS'           => [ ],
                },
            },
            'bison'   => {
                'toolopt' => [ '-y', ],
                'optvars' => {
                    'YACCFLAGS'           => [ ],
                    'BISONFLAGS'          => [ ],
                },
            },
        },
        'lex'      => {
            'lex'     => {
                'toolopt' => [ ],
                'optvars' => {
                    'LEXFLAGS'            => [ ],
                },
            },
            'flex'    => {
                'toolopt' => [ '-l', ],
                'optvars' => {
                    'LEXFLAGS'            => [ ],
                    'FLEXFLAGS'           => [ ],
                },
            },
        },
        'flex'     => {
            'flex'    => {
                'toolopt' => [ '-l', ],
                'optvars' => {
                    'FLEXFLAGS'           => [ ],
                },
            },
        },
        'flex++'   => {
            'flex++'  => {
                'toolopt' => [ ],
                'optvars' => {
                    'FLEXXXFLAGS'         => [ ],
                },
            },
            'flex'    => {
                'toolopt' => [ '-++', ],
                'optvars' => {
                    'FLEXXXFLAGS'         => [ ],
                    'FLEXFLAGS'           => [ ],
                },
            },
        },
        'm4'       => {
            'm4'      => {
                'toolopt' => [ ],
                'optvars' => {
                    'M4FLAGS'             => [ ],
                },
            },
            'gm4'     => {
                'toolopt' => [ ],
                'optvars' => {
                    'M4FLAGS'             => [ ],
                    'GNUM4FLAGS'          => [ ],
                },
            },
        },
        'linkobj'  => {
            'ld'      => {
                'toolopt' => [ '-r', ],
                'optvars' => {
                    'LINKFLAGS'           => [ ],
                    'LINKOBJFLAGS'        => [ ],
                    'LDFLAGS'             => [ ],
                    'LDLINKFLAGS'         => [ ],
                    'LDLINKOBJFLAGS'      => [ ],
                },
                'forlang' => {
                    'asm'         => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKOBJFLAGS_ASM'           => [ ],
                            'LDFLAGS_ASM'                => [ ],
                            'LDLINKFLAGS_ASM'            => [ ],
                            'LDLINKOBJFLAGS_ASM'         => [ ],
                        },
                    },
                    'asm-cpp'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKOBJFLAGS_ASM'           => [ ],
                            'LDFLAGS_ASM'                => [ ],
                            'LDLINKFLAGS_ASM'            => [ ],
                            'LDLINKOBJFLAGS_ASM'         => [ ],
                        },
                    },
                    'c'           => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_C'                => [ ],
                            'LINKOBJFLAGS_C'             => [ ],
                            'LDFLAGS_C'                  => [ ],
                            'LDLINKFLAGS_C'              => [ ],
                            'LDLINKOBJFLAGS_C'           => [ ],
                        },
                    },
                    'c++'         => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_CXX'              => [ ],
                            'LINKOBJFLAGS_CXX'           => [ ],
                            'LDFLAGS_CXX'                => [ ],
                            'LDLINKFLAGS_CXX'            => [ ],
                            'LDLINKOBJFLAGS_CXX'         => [ ],
                        },
                    },
                    'objc'        => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJC'             => [ ],
                            'LINKOBJFLAGS_OBJC'          => [ ],
                            'LDFLAGS_OBJC'               => [ ],
                            'LDLINKFLAGS_OBJC'           => [ ],
                            'LDLINKOBJFLAGS_OBJC'        => [ ],
                        },
                    },
                    'objc++'      => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJCXX'           => [ ],
                            'LINKOBJFLAGS_OBJCXX'        => [ ],
                            'LDFLAGS_OBJCXX'             => [ ],
                            'LDLINKFLAGS_OBJCXX'         => [ ],
                            'LDLINKOBJFLAGS_OBJCXX'      => [ ],
                        },
                    },
                },
            },
        },
        'linklib'  => {
            'ar'      => {
                'toolopt' => [ ],
                'optvars' => {
                    'ARFLAGS'             => [ ],
                },
            },
            'ranlib'  => {
                'toolopt' => [ ],
                'optvars' => {
                    'RANLIBFLAGS'         => [ ],
                },
            },
            'libtool' => {
                'toolopt' => [ '-static', ],
                'optvars' => {
                    'LINKLIBFLAGS'        => [ ],
                    'LIBTOOLFLAGS'        => [ ],
                    'LIBTOOLLINKFLAGS'    => [ ],
                    'LIBTOOLLINKLIBFLAGS' => [ ],
                },
            },
        },
        'linkdll'  => {
            'ld'      => {
                'toolopt' => [ '-shared', ],
                'optvars' => {
                    'LINKFLAGS'           => [ ],
                    'LINKDLLFLAGS'        => [ ],
                    'LDFLAGS'             => [ ],
                    'LDLINKFLAGS'         => [ ],
                    'LDLINKDLLFLAGS'      => [ ],
                },
                'forlang' => {
                    'asm'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKDLLFLAGS_ASM'           => [ ],
                            'LDLINKFLAGS_ASM'            => [ ],
                            'LDLINKDLLFLAGS_ASM'         => [ ],
                        },
                    },
                    'asm-cpp' => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKDLLFLAGS_ASM'           => [ ],
                            'LDLINKFLAGS_ASM'            => [ ],
                            'LDLINKDLLFLAGS_ASM'         => [ ],
                        },
                    },
                    'c'       => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_C'                => [ ],
                            'LINKDLLFLAGS_C'             => [ ],
                            'LDLINKFLAGS_C'              => [ ],
                            'LDLINKDLLFLAGS_C'           => [ ],
                        },
                    },
                    'c++'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_CXX'              => [ ],
                            'LINKDLLFLAGS_CXX'           => [ ],
                            'LDLINKFLAGS_CXX'            => [ ],
                            'LDLINKDLLFLAGS_CXX'         => [ ],
                        },
                    },
                    'objc'    => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJC'             => [ ],
                            'LINKDLLFLAGS_OBJC'          => [ ],
                            'LDLINKFLAGS_OBJC'           => [ ],
                            'LDLINKDLLFLAGS_OBJC'        => [ ],
                        },
                    },
                    'objc++'  => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJCXX'           => [ ],
                            'LINKDLLFLAGS_OBJCXX'        => [ ],
                            'LDLINKFLAGS_OBJCXX'         => [ ],
                            'LDLINKDLLFLAGS_OBJCXX'      => [ ],
                        },
                    },
                },
            },
            'libtool' => {
                'toolopt' => [ '-dynamic', ],
                'optvars' => {
                    'LINKFLAGS'           => [ ],
                    'LINKDLLFLAGS'        => [ ],
                    'LIBTOOLLINKFLAGS'    => [ ],
                    'LIBTOOLLINKDLLFLAGS' => [ ],
                },
                'forlang' => {
                    'asm'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKDLLFLAGS_ASM'           => [ ],
                            'LIBTOOLLINKFLAGS_ASM'       => [ ],
                            'LIBTOOLLINKDLLFLAGS_ASM'    => [ ],
                        },
                    },
                    'asm-cpp' => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKDLLFLAGS_ASM'           => [ ],
                            'LIBTOOLLINKFLAGS_ASM'       => [ ],
                            'LIBTOOLLINKDLLFLAGS_ASM'    => [ ],
                        },
                    },
                    'c'       => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_C'                => [ ],
                            'LINKDLLFLAGS_C'             => [ ],
                            'LIBTOOLLINKFLAGS_C'         => [ ],
                            'LIBTOOLLINKDLLFLAGS_C'      => [ ],
                        },
                    },
                    'c++'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_CXX'              => [ ],
                            'LINKDLLFLAGS_CXX'           => [ ],
                            'LIBTOOLLINKFLAGS_CXX'       => [ ],
                            'LIBTOOLLINKDLLFLAGS_CXX'    => [ ],
                        },
                    },
                    'objc'    => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJC'             => [ ],
                            'LINKDLLFLAGS_OBJC'          => [ ],
                            'LIBTOOLLINKFLAGS_OBJC'      => [ ],
                            'LIBTOOLLINKDLLFLAGS_OBJC'   => [ ],
                        },
                    },
                    'objc++'  => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJCXX'           => [ ],
                            'LINKDLLFLAGS_OBJCXX'        => [ ],
                            'LIBTOOLLINKFLAGS_OBJCXX'    => [ ],
                            'LIBTOOLLINKDLLFLAGS_OBJCXX' => [ ],
                        },
                    },
                },
            },
            'clang'   => {
                'toolopt' => [ '-shared', ],
                'optvars' => {
                    'LINKFLAGS'           => [ ],
                    'LINKDLLFLAGS'        => [ ],
                    'CLANGLINKFLAGS'      => [ ],
                    'CLANGLINKDLLFLAGS'   => [ ],
                },
                'forlang' => {
                    'asm'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'           => [ ],
                            'LINKDLLFLAGS_ASM'        => [ ],
                            'CLANGLINKFLAGS_ASM'      => [ ],
                            'CLANGLINKDLLFLAGS_ASM'   => [ ],
                        },
                    },
                    'asm-cpp' => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'           => [ ],
                            'LINKDLLFLAGS_ASM'        => [ ],
                            'CLANGLINKFLAGS_ASM'      => [ ],
                            'CLANGLINKDLLFLAGS_ASM'   => [ ],
                        },
                    },
                    'c'       => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_C'             => [ ],
                            'LINKDLLFLAGS_C'          => [ ],
                            'CLANGLINKFLAGS_C'        => [ ],
                            'CLANGLINKDLLFLAGS_C'     => [ ],
                        },
                    },
                    'c++'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_CXX'              => [ ],
                            'LINKDLLFLAGS_CXX'           => [ ],
                            'CLANGLINKFLAGS_CXX'         => [ ],
                            'CLANGLINKDLLFLAGS_CXX'      => [ ],
                        },
                    },
                    'objc'    => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJC'             => [ ],
                            'LINKDLLFLAGS_OBJC'          => [ ],
                            'CLANGLINKFLAGS_OBJC'        => [ ],
                            'CLANGLINKDLLFLAGS_OBJC'     => [ ],
                        },
                    },
                    'objc++'  => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJCXX'           => [ ],
                            'LINKDLLFLAGS_OBJCXX'        => [ ],
                            'CLANGLINKFLAGS_OBJCXX'      => [ ],
                            'CLANGLINKDLLFLAGS_OBJCXX'   => [ ],
                        },
                    },
                },
            },
            'clang++' => {
                'toolopt' => [ '-shared', ],
                'optvars' => {
                    'LINKFLAGS'           => [ ],
                    'LINKDLLFLAGS'        => [ ],
                    'CLANGXXLINKFLAGS'    => [ ],
                    'CLANGXXLINKDLLFLAGS' => [ ],
                },
                'forlang' => {
                    'asm'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKDLLFLAGS_ASM'           => [ ],
                            'CLANGXXLINKFLAGS_ASM'       => [ ],
                            'CLANGXXLINKDLLFLAGS_ASM'    => [ ],
                        },
                    },
                    'asm-cpp' => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKDLLFLAGS_ASM'           => [ ],
                            'CLANGXXLINKFLAGS_ASM'       => [ ],
                            'CLANGXXLINKDLLFLAGS_ASM'    => [ ],
                        },
                    },
                    'c'       => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_C'                => [ ],
                            'LINKDLLFLAGS_C'             => [ ],
                            'CLANGXXLINKFLAGS_C'         => [ ],
                            'CLANGXXLINKDLLFLAGS_C'      => [ ],
                        },
                    },
                    'c++'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_CXX'              => [ ],
                            'LINKDLLFLAGS_CXX'           => [ ],
                            'CLANGXXLINKFLAGS_CXX'       => [ ],
                            'CLANGXXLINKDLLFLAGS_CXX'    => [ ],
                        },
                    },
                    'objc'    => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJC'             => [ ],
                            'LINKDLLFLAGS_OBJC'          => [ ],
                            'CLANGXXLINKFLAGS_OBJC'      => [ ],
                            'CLANGXXLINKDLLFLAGS_OBJC'   => [ ],
                        },
                    },
                    'objc++'  => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJCXX'           => [ ],
                            'LINKDLLFLAGS_OBJCXX'        => [ ],
                            'CLANGXXLINKFLAGS_OBJCXX'    => [ ],
                            'CLANGXXLINKDLLFLAGS_OBJCXX' => [ ],
                        },
                    },
                },
            },
            'cc'      => {
                'toolopt' => [ '-shared', ],
                'optvars' => {
                    'LINKFLAGS'           => [ ],
                    'LINKDLLFLAGS'        => [ ],
                },
                'forlang' => {
                    'asm'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKDLLFLAGS_ASM'           => [ ],
                        },
                    },
                    'asm-cpp' => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKDLLFLAGS_ASM'           => [ ],
                        },
                    },
                    'c'       => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_C'                => [ ],
                            'LINKDLLFLAGS_C'             => [ ],
                        },
                    },
                    'c++'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_C'                => [ ],
                            'LINKDLLFLAGS_C'             => [ ],
                        },
                    },
                    'objc'    => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJC'             => [ ],
                            'LINKDLLFLAGS_OBJC'          => [ ],
                        },
                    },
                    'objc++'  => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJCXX'           => [ ],
                            'LINKDLLFLAGS_OBJCXX'        => [ ],
                        },
                    },
                },
            },
            'c++'     => {
                'toolopt' => [ '-shared', ],
                'optvars' => {
                    'LINKFLAGS'           => [ ],
                    'LINKDLLFLAGS'        => [ ],
                },
                'forlang' => {
                    'asm'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKDLLFLAGS_ASM'           => [ ],
                        },
                    },
                    'asm-cpp' => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKDLLFLAGS_ASM'           => [ ],
                        },
                    },
                    'c'       => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_C'                => [ ],
                            'LINKDLLFLAGS_C'             => [ ],
                        },
                    },
                    'c++'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_CXX'              => [ ],
                            'LINKDLLFLAGS_CXX'           => [ ],
                        },
                    },
                    'objc'    => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJC'             => [ ],
                            'LINKDLLFLAGS_OBJC'          => [ ],
                        },
                    },
                    'objc++'  => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJCXX'           => [ ],
                            'LINKDLLFLAGS_OBJCXX'        => [ ],
                        },
                    },
                },
            },
            'gcc'     => {
                'toolopt' => [ '-shared', ],
                'optvars' => {
                    'LINKFLAGS'           => [ ],
                    'LINKDLLFLAGS'        => [ ],
                    'GNUCLINKFLAGS'       => [ ],
                    'GNUCLINKDLLFLAGS'    => [ ],
                },
                'forlang' => {
                    'asm'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKDLLFLAGS_ASM'           => [ ],
                            'GNUCLINKFLAGS_ASM'          => [ ],
                            'GNUCLINKDLLFLAGS_ASM'       => [ ],
                        },
                    },
                    'asm-cpp' => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKDLLFLAGS_ASM'           => [ ],
                            'GNUCLINKFLAGS_ASM'          => [ ],
                            'GNUCLINKDLLFLAGS_ASM'       => [ ],
                        },
                    },
                    'c'       => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_C'                => [ ],
                            'LINKDLLFLAGS_C'             => [ ],
                            'GNUCLINKFLAGS_C'            => [ ],
                            'GNUCLINKDLLFLAGS_C'         => [ ],
                        },
                    },
                    'c++'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_CXX'              => [ ],
                            'LINKDLLFLAGS_CXX'           => [ ],
                            'GNUCLINKFLAGS_CXX'          => [ ],
                            'GNUCLINKDLLFLAGS_CXX'       => [ ],
                        },
                    },
                    'objc'    => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJC'             => [ ],
                            'LINKDLLFLAGS_OBJC'          => [ ],
                            'GNUCLINKFLAGS_OBJC'         => [ ],
                            'GNUCLINKDLLFLAGS_OBJC'      => [ ],
                        },
                    },
                    'objc++'  => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJCXX'           => [ ],
                            'LINKDLLFLAGS_OBJCXX'        => [ ],
                            'GNUCLINKFLAGS_OBJCXX'       => [ ],
                            'GNUCLINKDLLFLAGS_OBJCXX'    => [ ],
                        },
                    },
                },
            },
            'g++'     => {
                'toolopt' => [ '-shared', ],
                'optvars' => {
                    'LINKFLAGS'           => [ ],
                    'LINKDLLFLAGS'        => [ ],
                    'GNUCXXLINKFLAGS'     => [ ],
                    'GNUCXXLINKDLLFLAGS'  => [ ],
                },
                'forlang' => {
                    'asm'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKDLLFLAGS_ASM'           => [ ],
                            'GNUCXXLINKFLAGS_ASM'        => [ ],
                            'GNUCXXLINKDLLFLAGS_ASM'     => [ ],
                        },
                    },
                    'asm-cpp' => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKDLLFLAGS_ASM'           => [ ],
                            'GNUCXXLINKFLAGS_ASM'        => [ ],
                            'GNUCXXLINKDLLFLAGS_ASM'     => [ ],
                        },
                    },
                    'c'       => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_C'                => [ ],
                            'LINKDLLFLAGS_C'             => [ ],
                            'GNUCXXLINKFLAGS_C'          => [ ],
                            'GNUCXXLINKDLLFLAGS_C'       => [ ],
                        },
                    },
                    'c++'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_CXX'              => [ ],
                            'LINKDLLFLAGS_CXX'           => [ ],
                            'GNUCXXLINKFLAGS_CXX'        => [ ],
                            'GNUCXXLINKDLLFLAGS_CXX'     => [ ],
                        },
                    },
                    'objc'    => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJC'             => [ ],
                            'LINKDLLFLAGS_OBJC'          => [ ],
                            'GNUCXXLINKFLAGS_OBJC'       => [ ],
                            'GNUCXXLINKDLLFLAGS_OBJC'    => [ ],
                        },
                    },
                    'objc++'  => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJCXX'           => [ ],
                            'LINKDLLFLAGS_OBJCXX'        => [ ],
                            'GNUCXXLINKFLAGS_OBJCXX'     => [ ],
                            'GNUCXXLINKDLLFLAGS_OBJCXX'  => [ ],
                        },
                    },
                },
            },
        },
        'linkexe'  => {
            'ld'      => {
                'toolopt' => [ '-shared', ],
                'optvars' => {
                    'LINKFLAGS'           => [ ],
                    'LINKEXEFLAGS'        => [ ],
                    'LDFLAGS'             => [ ],
                    'LDEXEFLAGS'          => [ ],
                },
                'forlang' => {
                    'asm'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKEXEFLAGS_ASM'           => [ ],
                            'LDFLAGS_ASM'                => [ ],
                            'LDEXEFLAGS_ASM'             => [ ],
                        },
                    },
                    'asm-cpp' => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKEXEFLAGS_ASM'           => [ ],
                            'LDFLAGS_ASM'                => [ ],
                            'LDEXEFLAGS_ASM'             => [ ],
                        },
                    },
                    'c'       => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_C'                => [ ],
                            'LINKEXEFLAGS_C'             => [ ],
                            'LDFLAGS_C'                  => [ ],
                            'LDEXEFLAGS_C'               => [ ],
                        },
                    },
                    'c++'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_CXX'              => [ ],
                            'LINKEXEFLAGS_CXX'           => [ ],
                            'LDFLAGS_CXX'                => [ ],
                            'LDEXEFLAGS_CXX'             => [ ],
                        },
                    },
                    'objc'    => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJC'             => [ ],
                            'LINKEXEFLAGS_OBJC'          => [ ],
                            'LDFLAGS_OBJC'               => [ ],
                            'LDEXEFLAGS_OBJC'            => [ ],
                        },
                    },
                    'objc++'  => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJCXX'           => [ ],
                            'LINKEXEFLAGS_OBJCXX'        => [ ],
                            'LDFLAGS_OBJCXX'             => [ ],
                            'LDEXEFLAGS_OBJCXX'          => [ ],
                        },
                    },
               },
            },
            'clang'   => {
                'toolopt' => [ '-shared', ],
                'optvars' => {
                    'LINKFLAGS'           => [ ],
                    'LINKEXEFLAGS'        => [ ],
                    'CLANGLINKFLAGS'      => [ ],
                    'CLANGLINKEXEFLAGS'   => [ ],
                },
                'forlang' => {
                    'asm'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKEXEFLAGS_ASM'           => [ ],
                            'CLANGLINKFLAGS_ASM'         => [ ],
                            'CLANGLINKEXEFLAGS_ASM'      => [ ],
                        },
                    },
                    'asm-cpp' => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKEXEFLAGS_ASM'           => [ ],
                            'CLANGLINKFLAGS_ASM'         => [ ],
                            'CLANGLINKEXEFLAGS_ASM'      => [ ],
                        },
                    },
                    'c'       => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_C'                => [ ],
                            'LINKEXEFLAGS_C'             => [ ],
                            'CLANGLINKFLAGS_C'           => [ ],
                            'CLANGLINKEXEFLAGS_C'        => [ ],
                        },
                    },
                    'c++'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_CXX'              => [ ],
                            'LINKEXEFLAGS_CXX'           => [ ],
                            'CLANGLINKFLAGS_CXX'         => [ ],
                            'CLANGLINKEXEFLAGS_CXX'      => [ ],
                        },
                    },
                    'objc'    => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJC'             => [ ],
                            'LINKEXEFLAGS_OBJC'          => [ ],
                            'CLANGLINKFLAGS_OBJC'        => [ ],
                            'CLANGLINKEXEFLAGS_OBJC'     => [ ],
                        },
                    },
                    'objc++'  => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJCXX'           => [ ],
                            'LINKEXEFLAGS_OBJCXX'        => [ ],
                            'CLANGLINKFLAGS_OBJCXX'      => [ ],
                            'CLANGLINKEXEFLAGS_OBJCXX'   => [ ],
                        },
                    },
                },
            },
            'clang++' => {
                'toolopt' => [ '-shared', ],
                'optvars' => {
                    'LINKFLAGS'           => [ ],
                    'LINKEXEFLAGS'        => [ ],
                    'CLANGXXLINKFLAGS'    => [ ],
                    'CLANGXXLINKEXEFLAGS' => [ ],
                },
                'forlang' => {
                    'asm'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKEXEFLAGS_ASM'           => [ ],
                            'CLANGXXLINKFLAGS_ASM'       => [ ],
                            'CLANGXXLINKEXEFLAGS_ASM'    => [ ],
                        },
                    },
                    'asm-cpp' => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKEXEFLAGS_ASM'           => [ ],
                            'CLANGXXLINKFLAGS_ASM'       => [ ],
                            'CLANGXXLINKEXEFLAGS_ASM'    => [ ],
                        },
                    },
                    'c'       => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_C'                => [ ],
                            'LINKEXEFLAGS_C'             => [ ],
                            'CLANGXXLINKFLAGS_C'         => [ ],
                            'CLANGXXLINKEXEFLAGS_C'      => [ ],
                        },
                    },
                    'c++'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_CXX'              => [ ],
                            'LINKEXEFLAGS_CXX'           => [ ],
                            'CLANGXXLINKFLAGS_CXX'       => [ ],
                            'CLANGXXLINKEXEFLAGS_CXX'    => [ ],
                        },
                    },
                    'objc'    => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJC'             => [ ],
                            'LINKEXEFLAGS_OBJC'          => [ ],
                            'CLANGXXLINKFLAGS_OBJC'      => [ ],
                            'CLANGXXLINKEXEFLAGS_OBJC'   => [ ],
                        },
                    },
                    'objc++'  => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJCXX'           => [ ],
                            'LINKEXEFLAGS_OBJCXX'        => [ ],
                            'CLANGXXLINKFLAGS_OBJCXX'    => [ ],
                            'CLANGXXLINKEXEFLAGS_OBJCXX' => [ ],
                        },
                    },
                },
            },
            'cc'      => {
                'toolopt' => [ '-shared', ],
                'optvars' => {
                    'LINKFLAGS'           => [ ],
                    'LINKEXEFLAGS'        => [ ],
                },
                'forlang' => {
                    'asm'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKEXEFLAGS_ASM'           => [ ],
                        },
                    },
                    'asm-cpp' => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKEXEFLAGS_ASM'           => [ ],
                        },
                    },
                    'c'       => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_C'                => [ ],
                            'LINKEXEFLAGS_C'             => [ ],
                        },
                    },
                    'c++'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_C'                => [ ],
                            'LINKEXEFLAGS_C'             => [ ],
                        },
                    },
                    'objc'    => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJC'             => [ ],
                            'LINKEXEFLAGS_OBJC'          => [ ],
                        },
                    },
                    'objc++'  => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJCXX'           => [ ],
                            'LINKEXEFLAGS_OBJCXX'        => [ ],
                        },
                    },
                },
            },
            'c++'     => {
                'toolopt' => [ '-shared', ],
                'optvars' => {
                    'LINKFLAGS'           => [ ],
                    'LINKEXEFLAGS'        => [ ],
                },
                'forlang' => {
                    'asm'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKEXEFLAGS_ASM'           => [ ],
                        },
                    },
                    'asm-cpp' => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKEXEFLAGS_ASM'           => [ ],
                        },
                    },
                    'c'       => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_C'                => [ ],
                            'LINKEXEFLAGS_C'             => [ ],
                        },
                    },
                    'c++'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_CXX'              => [ ],
                            'LINKEXEFLAGS_CXX'           => [ ],
                        },
                    },
                    'objc'    => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJC'             => [ ],
                            'LINKEXEFLAGS_OBJC'          => [ ],
                        },
                    },
                    'objc++'  => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJCXX'           => [ ],
                            'LINKEXEFLAGS_OBJCXX'        => [ ],
                        },
                    },
                },
            },
            'gcc'     => {
                'toolopt' => [ '-shared', ],
                'optvars' => {
                    'LINKFLAGS'           => [ ],
                    'LINKEXEFLAGS'        => [ ],
                    'GNUCLINKFLAGS'       => [ ],
                    'GNUCLINKEXEFLAGS'    => [ ],
                },
                'forlang' => {
                    'asm'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKEXEFLAGS_ASM'           => [ ],
                            'GNUCLINKFLAGS_ASM'          => [ ],
                            'GNUCLINKEXEFLAGS_ASM'       => [ ],
                        },
                    },
                    'asm-cpp' => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKEXEFLAGS_ASM'           => [ ],
                            'GNUCLINKFLAGS_ASM'          => [ ],
                            'GNUCLINKEXEFLAGS_ASM'       => [ ],
                        },
                    },
                    'c'       => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_C'                => [ ],
                            'LINKEXEFLAGS_C'             => [ ],
                            'GNUCLINKFLAGS_C'            => [ ],
                            'GNUCLINKEXEFLAGS_C'         => [ ],
                        },
                    },
                    'c++'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_CXX'              => [ ],
                            'LINKEXEFLAGS_CXX'           => [ ],
                            'GNUCLINKFLAGS_CXX'          => [ ],
                            'GNUCLINKEXEFLAGS_CXX'       => [ ],
                        },
                    },
                    'objc'    => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJC'             => [ ],
                            'LINKEXEFLAGS_OBJC'          => [ ],
                            'GNUCLINKFLAGS_OBJC'         => [ ],
                            'GNUCLINKEXEFLAGS_OBJC'      => [ ],
                        },
                    },
                    'objc++'  => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJCXX'           => [ ],
                            'LINKEXEFLAGS_OBJCXX'        => [ ],
                            'GNUCLINKFLAGS_OBJCXX'       => [ ],
                            'GNUCLINKEXEFLAGS_OBJCXX'    => [ ],
                        },
                    },
                },
            },
            'g++'     => {
                'toolopt' => [ ],
                'optvars' => {
                    'LINKFLAGS'           => [ ],
                    'LINKEXEFLAGS'        => [ ],
                    'GNUCXXLINKFLAGS'     => [ ],
                    'GNUCXXLINKEXEFLAGS'  => [ ],
                },
                'forlang' => {
                    'asm'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKEXEFLAGS_ASM'           => [ ],
                            'GNUCXXLINKFLAGS_ASM'        => [ ],
                            'GNUCXXLINKEXEFLAGS_ASM'     => [ ],
                        },
                    },
                    'asm-cpp' => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_ASM'              => [ ],
                            'LINKEXEFLAGS_ASM'           => [ ],
                            'GNUCXXLINKFLAGS_ASM'        => [ ],
                            'GNUCXXLINKEXEFLAGS_ASM'     => [ ],
                        },
                    },
                    'c'       => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_C'                => [ ],
                            'LINKEXEFLAGS_C'             => [ ],
                            'GNUCXXLINKFLAGS_C'          => [ ],
                            'GNUCXXLINKEXEFLAGS_C'       => [ ],
                        },
                    },
                    'c++'     => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_CXX'              => [ ],
                            'LINKEXEFLAGS_CXX'           => [ ],
                            'GNUCXXLINKFLAGS_CXX'        => [ ],
                            'GNUCXXLINKEXEFLAGS_CXX'     => [ ],
                        },
                    },
                    'objc'    => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJC'             => [ ],
                            'LINKEXEFLAGS_OBJC'          => [ ],
                            'GNUCXXLINKFLAGS_OBJC'       => [ ],
                            'GNUCXXLINKEXEFLAGS_OBJC'    => [ ],
                        },
                    },
                    'objc++'  => {
                        'toolopt' => [ ],
                        'optvars' => {
                            'LINKFLAGS_OBJCXX'           => [ ],
                            'LINKEXEFLAGS_OBJCXX'        => [ ],
                            'GNUCXXLINKFLAGS_OBJCXX'     => [ ],
                            'GNUCXXLINKEXEFLAGS_OBJCXX'  => [ ],
                        },
                    },
                },
            },
        },
        'linkfat'  => {
            'lipo'    => {
                'toolopt' => [ ],
                'optvars' => {
                    'LINKFATFLAGS'        => [ ],
                    'LIPOFLAGS'           => [ ],
                    'LIPOLINKFLAGS'       => [ ],
                    'LIPOLINKFATFLAGS'    => [ ],
                },
            },
        },
        'strings'  => {
            'strings' => {
                'toolopt' => [ ],
                'optvars' => {
                    'STRINGSFLAGS'        => [ ],
                },
            },
        },
        'size'     => {
            'size'    => {
                'toolopt' => [ ],
                'optvars' => {
                    'STRINGSFLAGS'        => [ ],
                },
            },
        },
        'size'     => {
            'size'    => {
                'toolopt' => [ ],
                'optvars' => {
                    'STRINGSFLAGS'        => [ ],
                },
            },
        },
        'indent'   => {
            'indent'  => {
                'toolopt' => [ ],
                'optvars' => {
                    'INDENTFLAGS'         => [ ],
                },
            },
        },
        'strip'    => {
            'strip'   => {
                'toolopt' => [ ],
                'optvars' => {
                    'STRIPFLAGS'          => [ ],
                },
            },
        },
        'nm'       => {
            'nm'      => {
                'toolopt' => [ ],
                'optvars' => {
                    'NMFLAGS'             => [ ],
                },
            },
        },
    );
    my @_base_dirs;
    my $_exec_prog = '';
#    my %_auto_conf;
    @_find_apps = qw{Applications};
    @_find_vers = qw{Contents Developer usr bin xcodebuild};
    @_find_plat = qw{Contents Developer Platforms};
    @_find_sdks = qw{Developer SDKs};
    @_find_tchn = qw{Contents Developer Toolchains};
    @_find_tool = qw{usr bin};

    my ($fun, $tbl);
    while (($fun, $tbl) = each(%_func_tool)) {
        map { push(@{$_tool_func{$_}}, $fun); } keys(%{$tbl});
    }

    my ($dir, $pth, $sub);
    if (Grace::Host->sysname() eq 'darwin') {
        @_find_apps = qw{Applications};
        $_exec_prog = '';

        # Search Spotlight metadata for installed Xcode.
        if (qx{/usr/bin/mdutil -s /} !~ m{disabled}o) {
            my $key = q{'kMDItemCFBundleIdentifier == "com.apple.dt.Xcode"'};
            my @dir = split(m{[\n\r]+}o, qx{/usr/bin/mdfind $key});
            push(@_base_dirs, @dir);
        }

        # Perform crude path search.
        $pth = File::Spec->catdir(File::Spec->rootdir(), @_find_apps);
        if (! opendir($dir, $pth)) {
            carp("Path '$pth': $!\n");
        } else {
            my @dir = (
                grep { -x File::Spec->catfile($_, @_find_vers) }
                map  { File::Spec->catdir($pth, $_) }
                grep { m{^Xcode.*\.app$}o }
                readdir($dir)
            );
            closedir($dir);
            push(@_base_dirs, @dir);
        }

        # Query the system for the default Xcode setup to use.
        $_dflt_conf = qx{/usr/bin/xcode-select -p};
    } else {
        # Running under emulation?  Darling on Linux, maybe?
        $_exec_prog = '';  # Prefix with emulator, maybe?
        @_base_dirs = ();  # Figure out how to fill this out.
        $_dflt_conf = undef;
    }

    # Scan directories and gather info on Xcode installations.
    foreach my $top (uniq(@_base_dirs)) {
        # Get Xcode version info.
        my ($out, $ver, $bld, $run);
         $run .= ($_exec_prog ? "$_exec_prog " : '');
         $run .= File::Spec->catfile($top, @_find_vers);
        next if (! ($out  = qx{$run -version}));
        ($ver) = ($out =~ m{^Xcode\s(\S+)\s*$}smo);
        ($bld) = ($out =~ m{^Build\s+version\s+(\S+)\s*$}smo);

        # Find present platform SDKs.
        my ($plt, %plt);
        $pth = File::Spec->catfile($top, @_find_plat);
        next if (! opendir($dir, $pth));
        foreach $plt (grep { m{\.platform$}io } readdir($dir)) {
            $sub = File::Spec->catdir($pth, $plt);
            next if (! -d $sub);
            $plt =~ s{\.platform$}{}io;
            $plt{$plt} = {
                'rootdir' => $sub,
            };
        }
        closedir($dir);

        # Tie platform SDKs to their platforms.
        my ($sdk, %sdk);
        while (($plt, $tbl) = each(%plt)) {
            $pth = File::Spec->catdir($tbl->{rootdir}, @_find_sdks);
            next if (! opendir($dir, $pth));
            foreach $sdk (grep { m{\.sdk$}o } readdir($dir)) {
                $sub = File::Spec->catdir($pth, $sdk);
                next if (! -d $sub);
                $sdk =~ s{\.sdk$}{}io;
                $plt{$plt}->{sdkpath}->{$sdk} = $sub;
                if (! $plt{$plt}->{dfltsdk} || ($plt eq $sdk)) {
                    $plt{$plt}->{dfltsdk} = $sdk;
                } elsif ($plt{$plt}->{dfltsdk} ne $plt) {
                    my ($oldver) = ($plt{$plt}->{dfltsdk} =~ m{^$plt(.*)$});
                    my ($newver) = ($sdk =~ m{^$plt(.*)$});
                    if (Version::Compare::version_compare($newver, $oldver) >= 0) {
                        $plt{$plt}->{dfltsdk} = $sdk;
                    }
                }
            }
            closedir($dir);
        }

        # Find present toolchains.
        my ($chn, %chn);
        $pth = File::Spec->catdir($top, @_find_tchn);
        next if (! opendir($dir, $pth));
        foreach $chn (grep { m{\.xctoolchain$}io } readdir($dir)) {
            $sub =  File::Spec->catdir($pth, $chn);
            $chn =~ s{\.xctoolchain$}{}io;
            $chn{$chn} = $sub;
        }
        closedir($dir);

        # Find supported languages and preferred tools.
        while (($chn, $pth) = each(%chn)) {
            $pth = File::Spec->catdir($pth, @_find_tool);
            # Not a directory we can plumb.
            next if (! opendir($dir, $pth));
            my ($bin, $utl, %utl);
            # Scan the directory for tool binaries.
            foreach (grep { ! m{^\.\.?$}o } readdir($dir)) {
                # Not a known tool.
                next if (! $_tool_func{$_});
                $bin = File::Spec->catfile($pth, $_);
                # Not an executable program.
                next if (! -f $bin || ! -x $bin);
                # Place the tool in its proper language bins.
                foreach my $fun (@{$_tool_func{$_}}) {
                    if (! $utl{$fun}
                     || (($_lang_pref{$fun} || '') eq $_)
                     || (($_util_pref{$fun} || '') eq $_))
                    {
                        $utl{$fun} = $bin;
                    }
                }
            }
            closedir($dir);

            my $key = "Xcode-$ver.$bld-$chn";

            $chn = {
                'knownas' => $key,
                'toolchn' => $chn,
                'rootdir' => $top,
                'version' => $ver,
                'buildno' => $bld,
                'systems' => \%plt,
                'toolmap' => \%utl,
                'langmap' => { map { ($_ => $utl{$_}) } keys(%_lang_pref) },
                'utilmap' => { map { ($_ => $utl{$_}) } keys(%_util_pref) },
            };

            $_auto_conf{$top} = bless($chn);
            Grace::Toolset::register(__PACKAGE__, $key, $chn);
        }
    }
}

sub default () {
    return $_auto_conf{$_dflt_conf};
}

sub languages () {
    my $self = shift;
#print(STDERR __PACKAGE__."->languages()\n");
    return keys(%{$self->{langmap}});
}

sub utilities () {
    my $self = shift;
#print(STDERR __PACKAGE__."->utilities()\n");
    return keys(%{$self->{utilmap}});
}

sub platforms () {
    my $self = shift;
#print(STDERR __PACKAGE__."->platforms()\n");
    return keys(%{$self->{systems}});
}

sub driver () {
#print(STDERR __PACKAGE__."->driver()\n");
    return __PACKAGE__;
}

sub tool ($) {
    my $self = shift;
    my $tool = shift;
#print(STDERR __PACKAGE__."->tool($tool)\n");
    return $self->{toolmap}->{$tool};
}

sub toolconfig ($) {
    my $self = shift;
    my $func = shift;
#print(STDERR __PACKAGE__."->toolconfig($func)\n");
    return $_func_tool{$func}{$self->{toolmap}->{$func}};
}

1;
