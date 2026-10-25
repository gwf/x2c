/*  parse-reports.x -- package, binding, and alias diagnostics
*/

#pragma once

macro Stmt $fail.parse_alias_name(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "expected an alias identifier after 'as'",
    $site, NULL);

macro Stmt $fail.parse_decl_bound(Expr $c, Expr $site, Expr $exact) =>
  $c.report_error(
    <parse>, %"declaration '${$exact}' is already bound",
    $site, %("prior binding: '${$exact}'"));

macro Stmt $fail.parse_package_member(
  Expr $c, Expr $site, Expr $name, Expr $member) =>
  $c.report_error(
    <parse>,
    %"package '${$name}' has no public name '${$member}'",
    $site, NULL);
