import { readFileSync } from 'node:fs';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, collection, query, where, getDocs, serverTimestamp, writeBatch, Timestamp } from 'firebase/firestore';

let env;
const roles = { admin: 'المدير', production: 'نجاة', sales: 'سلمى', marketing: 'حسن', reviewer: 'لقمان' };
const path = name => `workspaces/zizouit/${name}`;
const db = uid => env.authenticatedContext(uid, {email_verified:true}).firestore();
const command = uid => ({uid,kind:uid === 'sales' ? 'sale' : 'produceFromRecipe',arguments:{recipeId:'Z1',output:4},status:'pending',created:serverTimestamp()});
before(async () => {
  env = await initializeTestEnvironment({projectId:'demo-zizouit-manager',firestore:{host:'127.0.0.1',port:8085,rules:readFileSync(new URL('../firestore.rules',import.meta.url),'utf8')}});
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    const store = context.firestore();
    for (const [uid,role] of Object.entries(roles)) await setDoc(doc(store,path(`members/${uid}`)),{role,active:true});
    await setDoc(doc(store,path('members/disabled')),{role:'سلمى',active:false});
    await setDoc(doc(store,path('state/private')),{json:'{"debts":[{"party":"PRIVATE"}]}',revision:1,updated:Timestamp.now()});
    await setDoc(doc(store,path('state/public')),{json:'{"products":[]}',revision:1,updated:Timestamp.now()});
  });
});

test('Unauthenticated and unassigned users cannot read either dataset', async () => {
  for (const store of [env.unauthenticatedContext().firestore(),db('outsider')]) {
    await assertFails(getDoc(doc(store,path('state/public'))));
    await assertFails(getDoc(doc(store,path('state/private'))));
  }
});
test('An unverified account cannot use assigned admin or staff permissions', async () => {
  for (const uid of ['admin','sales']) {
    const store = env.authenticatedContext(uid, {email_verified:false}).firestore();
    await assertFails(getDoc(doc(store,path('state/public'))));
    await assertFails(getDoc(doc(store,path('state/private'))));
    await assertFails(getDoc(doc(store,path(`members/${uid}`))));
  }
});
test('Matching the owner email never grants an unassigned UID administrator access', async () => {
  const store = env.authenticatedContext('outsider', {email:'medsbai451@gmail.com',email_verified:true}).firestore();
  await assertFails(getDoc(doc(store,path('state/private'))));
  await assertFails(setDoc(doc(store,path('members/outsider')),{role:'المدير',active:true}));
});
test('Only the admin reads money/debts; staff read sanitized public data', async () => {
  await assertSucceeds(getDoc(doc(db('admin'),path('state/private'))));
  for (const uid of ['production','sales','marketing','reviewer']) {
    await assertSucceeds(getDoc(doc(db(uid),path('state/public'))));
    await assertFails(getDoc(doc(db(uid),path('state/private'))));
  }
});
test('Staff cannot elevate themselves, change other roles, or list members', async () => {
  await assertSucceeds(getDoc(doc(db('sales'),path('members/sales'))));
  await assertFails(setDoc(doc(db('sales'),path('members/sales')),{role:'المدير',active:true}));
  await assertFails(updateDoc(doc(db('sales'),path('members/production')),{role:'المدير'}));
  await assertFails(getDocs(collection(db('sales'),path('members'))));
});
test('Admin assigns roles but cannot accidentally disable their own account', async () => {
  await assertSucceeds(setDoc(doc(db('admin'),path('members/new')),{role:'نجاة',active:true}));
  await assertFails(updateDoc(doc(db('admin'),path('members/admin')),{active:false}));
});
test('Staff cannot overwrite canonical or public stock data', async () => {
  const state = {json:'{}',revision:2,updated:serverTimestamp()};
  await assertFails(setDoc(doc(db('production'),path('state/public')),state));
  await assertFails(setDoc(doc(db('sales'),path('state/private')),state));
});
test('Allowed worker commands are immutable, owned, and role-bound', async () => {
  const store = db('production');
  await assertSucceeds(getDoc(doc(store,path('commands/not-yet-created'))));
  await assertSucceeds(setDoc(doc(store,path('commands/c1')),command('production')));
  await assertFails(updateDoc(doc(store,path('commands/c1')),{status:'applied'}));
  await assertFails(setDoc(doc(store,path('commands/c2')),{...command('production'),uid:'admin'}));
  await assertFails(setDoc(doc(db('sales'),path('commands/c3')),{...command('sales'),kind:'produce'}));
  await assertFails(setDoc(doc(db('reviewer'),path('commands/c4')),command('reviewer')));
  await assertFails(setDoc(doc(store,path('commands/c5')),{...command('production'),role:'المدير'}));
});
test('Staff read their own queue, not another user or unrestricted queries', async () => {
  await assertSucceeds(setDoc(doc(db('sales'),path('commands/c1')),command('sales')));
  await assertSucceeds(getDocs(query(collection(db('sales'),path('commands')),where('uid','==','sales'))));
  await assertFails(getDocs(collection(db('sales'),path('commands'))));
  await assertFails(getDoc(doc(db('production'),path('commands/c1'))));
});
test('Admin processing may change status but cannot rewrite the original command', async () => {
  await assertSucceeds(setDoc(doc(db('sales'),path('commands/c1')),command('sales')));
  await assertFails(updateDoc(doc(db('admin'),path('commands/c1')),{arguments:{output:999},status:'applied',processed:serverTimestamp(),processedBy:'admin'}));
  await assertSucceeds(updateDoc(doc(db('admin'),path('commands/c1')),{status:'rejected',error:'stock insufficient',processed:serverTimestamp(),processedBy:'admin'}));
  await assertFails(updateDoc(doc(db('admin'),path('commands/c1')),{status:'applied',processed:serverTimestamp(),processedBy:'admin'}));
});
test('Admin state revisions must advance together in one atomic batch', async () => {
  const store = db('admin');
  const batch = writeBatch(store);
  for (const visibility of ['private','public']) batch.set(doc(store,path(`state/${visibility}`)),{json:'{}',revision:2,updated:serverTimestamp()});
  await assertSucceeds(batch.commit());
  await assertFails(setDoc(doc(store,path('state/private')),{json:'{}',revision:3,updated:serverTimestamp()}));
  const stale = writeBatch(store);
  for (const visibility of ['private','public']) stale.set(doc(store,path(`state/${visibility}`)),{json:'{}',revision:2,updated:serverTimestamp()});
  await assertFails(stale.commit());
});
test('Bootstrap state creation uses revision one and atomic public/private writes', async () => {
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(),'workspaces/empty/members/admin'),{role:'المدير',active:true});
  });
  const store = db('admin');
  const batch = writeBatch(store);
  for (const visibility of ['private','public']) batch.set(doc(store,`workspaces/empty/state/${visibility}`),{json:'{}',revision:1,updated:serverTimestamp()});
  await assertSucceeds(batch.commit());
});
test('Disabled users and users from other workspaces have no access', async () => {
  await assertFails(getDoc(doc(db('disabled'),path('state/public'))));
  await assertFails(setDoc(doc(db('disabled'),path('commands/c1')),command('disabled')));
  await assertFails(getDoc(doc(db('admin'),'workspaces/other/state/private')));
});
