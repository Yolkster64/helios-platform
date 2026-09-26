{
  "targets": [
    {
      "target_name": "particle_field",
      "sources": ["src/particle_field.cc"],
      "defines": ["NAPI_VERSION=8"],
      "cflags_cc": ["-std=c++17", "-Wall", "-Wextra"],
      "xcode_settings": { "CLANG_CXX_LANGUAGE_STANDARD": "c++17" },
      "msvs_settings": {
        "VCCLCompilerTool": { "AdditionalOptions": ["/std:c++17", "/W4"] }
      }
    }
  ]
}
