import { html, useState } from "../../vendor/preact-htm.js";
import { cloud } from "../cloud.js";
import { Icon, NavBar, Section, Segmented, go } from "../ui.js";
import { SyncStatus } from "./settings.js";

export function AccountView() {
  const [error, setError] = useState(null);
  if (!cloud.session) {
    go("settings");
    return null;
  }
  const signOut = async () => {
    await cloud.signOut();
    go("settings");
  };
  const deleteAccount = async () => {
    if (!confirm("Delete your account and all cloud data? This can't be undone.")) return;
    try {
      await cloud.deleteAccount();
      go("settings");
    } catch (e) {
      setError(e.message);
    }
  };
  return html`
    <${NavBar} title="Account" backTo="settings" backLabel="Settings" />
    <div class="page">
      <${Section} footer="Syncs when you open the page, a few seconds after each change, and every few minutes while it's open.">
        <div class="cell"><span class="cell-main">Email</span><span class="value">${cloud.session.email}</span></div>
        <div class="cell"><span class="cell-main">Status</span><span class="value"><${SyncStatus} /></span></div>
        <button class="cell action" disabled=${cloud.isSyncing} onClick=${() => cloud.sync()}><${Icon} name="sync" /> Sync now</button>
      <//>
      <${Section} footer="Your words stay in this browser after you sign out.">
        <button class="cell action" onClick=${signOut}>Sign out</button>
      <//>
      <${Section} footer="Permanently deletes your account and everything stored in the cloud. Data in this browser and on your devices is kept.">
        <button class="cell destructive" onClick=${deleteAccount}>Delete account</button>
      <//>
      ${error ? html`<div class="notice error" style="margin-top:12px">${error}</div>` : null}
    </div>`;
}

export function SignInView() {
  const [mode, setMode] = useState("signIn");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [working, setWorking] = useState(false);
  const [error, setError] = useState(null);
  const [info, setInfo] = useState(null);
  const canSubmit = email.includes("@") && password.length >= 6 && !working;
  const title = mode === "signIn" ? "Sign in" : "Create account";

  const submit = async (e) => {
    e.preventDefault();
    if (!canSubmit) return;
    setWorking(true);
    setError(null);
    setInfo(null);
    const address = email.trim().toLowerCase();
    try {
      if (mode === "signIn") {
        await cloud.signIn(address, password);
      } else if (!(await cloud.signUp(address, password))) {
        setInfo("Check your inbox for a confirmation email from Supabase, open the link, then come back and sign in.");
        setMode("signIn");
        return;
      }
      go("settings");
      cloud.sync();
    } catch (err) {
      setError(err.message);
    } finally {
      setWorking(false);
    }
  };

  return html`
    <${NavBar} title=${title} backTo="settings" backLabel="Settings" />
    <form class="page" onSubmit=${submit}>
      <div style="margin-top:16px"><${Segmented} label="Mode" options=${[["signIn", "Sign in"], ["signUp", "Create account"]]} value=${mode}
        onChange=${(m) => { setMode(m); setError(null); }} /></div>
      <${Section} footer=${mode === "signUp"
          ? "At least 6 characters. The words already in this browser are added to your new account."
          : "Use the same account as in the iPhone app. Words in this browser are merged with the ones in your account."}>
        <input class="text" type="email" placeholder="Email" autocomplete="email" autocapitalize="off" value=${email}
          onInput=${(e) => setEmail(e.currentTarget.value)} aria-label="Email" />
        <input class="text" type="password" placeholder="Password" autocomplete=${mode === "signUp" ? "new-password" : "current-password"}
          value=${password} onInput=${(e) => setPassword(e.currentTarget.value)} aria-label="Password" />
      <//>
      <${Section}>
        <button type="submit" class="cell action" disabled=${!canSubmit}>${title}${working ? "…" : ""}</button>
      <//>
      ${error ? html`<div class="notice error" style="margin-top:12px">${error}</div>` : null}
      ${info ? html`<div class="notice" style="margin-top:12px">${info}</div>` : null}
    </form>`;
}
