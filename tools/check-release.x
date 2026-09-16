#!/usr/bin/env -S x2c script
/*  check-release.x -- check a published release the way a user meets it

    The site names the version, the site's installer installs that compiler,
    and the site's package index installs a bundle for this platform.

      tools/check-release.x <version> [package]

    <version> has no leading v; [package] defaults to pcre2. X2C_SITE selects
    another site. Nothing outside a scratch prefix is touched, and the prefix
    is removed on exit.
*/
static int fail(String message) {
  Stderr.printf("check-release: %s\n", message);
  return 1;
}

if (!args) return fail(%"usage: tools/check-release.x <version> [package]");
String version = args.car().str().remove_prefix("v");
String package = args.cdr() ? args.cadr().str() : %"pcre2";
String site = Env.get("X2C_SITE");
if (!site) site = %"https://x2c-lang.dev";

Path work = Path.temp_dir();
defer work.remove_tree();

String published =
  %(curl -fsSL "$site/x2c-version.txt").job().output().strip("\n");
if (published != version)
  return fail(%"the site names $published, not $version");

String heading =
  %(curl -fsSL "$site/packages/index.txt").job().lines().car().str();
if (heading != %"# x2c package index for x2c $version")
  return fail(%"the site's package index is not for x2c $version");

Path prefix = work.join("x2c");
%((curl -fsSL "$site/install.sh") (sh -s "--" --version $version)).job()
  .options(%{env: {X2C_PREFIX: $prefix},
             stdout: ${work.join("install.log")}})
  .check();

Path x2c = prefix.join("bin/x2c");
String reported = %($x2c --version).job().output().strip("\n");
if (reported != %"x2c $version")
  return fail(%"install.sh installed $reported, not x2c $version");

%($x2c install -q $package).job().run();
List listed = %($x2c list).job().lines();
int installed = 0;
foreach (String row, listed)
  if (row.startswith(%"$package ") && row.endswith(" bundle")) installed = 1;
if (!installed) {
  String rows = String.join(" / ", listed);
  return fail(%"x2c install $package did not install a bundle: $rows");
}

printf("release %s: site, installer, and %s bundle check out\n",
       version, package);
