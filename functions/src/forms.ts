import {DocumentData,Timestamp}from'firebase-admin/firestore';
import{fail,id}from'./domain';
export const coreForms=['conduct','waiver'];
export const optionalForms=['photo-release','data-collection'];
export function requiredForms(e:DocumentData):string[]{if(!Array.isArray(e.requiredFormIds)||e.requiredFormIds.length>10)fail('failed-precondition','invalid-event','Invalid session agreements');return [...new Set([...coreForms,...e.requiredFormIds.map((f:unknown)=>id(f,'formId'))])];}
export function formBody(f:DocumentData):string{return typeof f.body==='string'?f.body:typeof f.content==='string'?f.content:'';}
export function publishedForm(f:DocumentData|undefined,now:number):f is DocumentData{return !!f&&f.published!==false&&f.status!=='draft'&&f.publishedAt instanceof Timestamp&&f.publishedAt.toMillis()<=now&&formBody(f).trim().length>0;}
