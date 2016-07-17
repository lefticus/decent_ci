AWS_ACCESS_KEY_ID         // decent_ci set, required by RunRegression.py in EnergyPlus run regression; coverage; post-build assets upload
AWS_SECRET_ACCESS_KEY     // decent_ci set, required by RunRegression.py in EnergyPlus run regression; coverage; post-build assets upload

GITHUB_TOKEN              // decent_ci set, required by EnergyPlus build process (changelog generation)

DECENT_CI_SKIP_DAILY_TASKS // user set, boolean: tells CI to not run daily tasks
DECENT_CI_BRANCH_FILTER    // user set, regex: tells CI which branches to be allowed to run
DECENT_CI_COMPILER_FILTER  // user set, regex: tells CI which compilers to be allowed to run
DECENT_CI_ALL_RELEASE      // user set, boolean: tells CI to do release packaging on all builds
