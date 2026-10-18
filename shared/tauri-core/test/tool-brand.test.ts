import { describe, expect, it } from 'vitest';
import { agentInitial, agentLogo, avatarLetter, shownPeople, signedInWords, signInLabel, signInLead, toolAsks, toolkitName, toolLook, toolPageHint, workFootnote, workLayout, workTitle } from '../src/core';

describe('tool brand', () => {
  it('colours a known tool in its own colour and the rest in the Memnox blue', () => {
    expect(toolLook('slack')).toEqual({ colour: '#4A154B', send: 'Send' });
    expect(toolLook('github').send).toBe('Comment');
    expect(toolLook('notion').send).toBe('Save');
    expect(toolLook('figma')).toEqual({ colour: '#1E86EE', send: 'Send' });
  });

  it('names a tool the way the person reads it', () => {
    expect(toolkitName('googledocs')).toBe('Google Docs');
    expect(toolkitName('github')).toBe('GitHub');
    expect(toolkitName('figma')).toBe('Figma');
  });

  it('offers three asks per tool, and three made up from the name for any other', () => {
    expect(toolAsks('slack')[0]).toBe('Catch me up on Slack since this morning');
    expect(toolAsks('figma')).toEqual(['What is new in Figma?', 'What needs me in Figma?', 'Summarise my week in Figma']);
  });

  it('hints at the talk key only when the tool is connected', () => {
    expect(toolPageHint('linear', true, 'Ctrl Alt Space')).toBe('Or press Ctrl Alt Space and ask anything about Linear.');
    expect(toolPageHint('linear', false, 'Ctrl Alt Space')).toBe('Ask anything and Memnox opens the sign in first.');
  });

  it('titles a work card by kind, a GitHub comment being a review comment', () => {
    expect(workTitle('message', 'slack')).toBe('Message on Slack');
    expect(workTitle('comment', 'github')).toBe('Review comment on GitHub');
    expect(workTitle('comment', 'linear')).toBe('Comment on Linear');
    expect(workTitle('email', 'gmail')).toBe('Email on Gmail');
    expect(workTitle('issue', 'figma')).toBe('Issue on Figma');
    expect(workTitle('whatever', 'figma')).toBe('Action on Figma');
  });

  it('lays out an issue and anything unknown the generic way', () => {
    expect(workLayout('message')).toBe('message');
    expect(workLayout('issue')).toBe('generic');
    expect(workLayout('other')).toBe('generic');
  });

  it('says what the footer says, in the order the Mac checks it', () => {
    expect(workFootnote({ sending: true, empty: true, changed: true }, 'Windows Hello')).toBe('Waiting for Windows Hello');
    expect(workFootnote({ sending: false, empty: true, changed: true }, 'x')).toBe('Write something to send.');
    expect(workFootnote({ sending: false, empty: false, changed: true }, 'x')).toBe('Your words go out as you wrote them.');
    expect(workFootnote({ sending: false, empty: false, changed: false }, 'x')).toBe('Nothing goes out until you send it.');
  });

  it('names three recipients and counts the rest', () => {
    expect(shownPeople(['a', 'b'])).toEqual({ shown: ['a', 'b'], more: 0 });
    expect(shownPeople(['a', 'b', 'c', 'd', 'e'])).toEqual({ shown: ['a', 'b', 'c'], more: 2 });
  });

  it('draws the avatar from the shown name, else from You', () => {
    expect(avatarLetter('ana')).toBe('A');
    expect(avatarLetter(undefined)).toBe('Y');
  });

  it('words the sign in pills as the Mac does', () => {
    expect(signedInWords('slack', 'ana')).toBe('Slack · ana');
    expect(signedInWords('slack', undefined)).toBe('Signed in to Slack');
    expect(signInLead([false, true])).toBe('Sign in');
    expect(signInLead([false])).toBe('Sign in to use');
    expect(signInLabel('gmail', true)).toBe('Sign in to Gmail again, with your own account');
  });
});

describe('agent logo', () => {
  it('wears the brand file by kind, Codex wearing OpenAI', () => {
    expect(agentLogo('agt_codex')).toBe('openai');
    expect(agentLogo('claude-desktop')).toBe('claude');
    expect(agentLogo('agt_gemini')).toBeUndefined();
  });

  it('stands in with the first letter', () => {
    expect(agentInitial('agt_gemini')).toBe('G');
    expect(agentInitial('hermes')).toBe('H');
  });
});
