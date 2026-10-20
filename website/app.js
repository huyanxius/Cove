(() => {
  const tabs = [...document.querySelectorAll('[data-mode]')];
  function selectMode(index) {
    const terminal = tabs[index].dataset.mode === 'terminal';
    tabs.forEach((tab, i) => {
      tab.setAttribute('aria-selected', String(i === index));
      tab.tabIndex = i === index ? 0 : -1;
    });
    document.querySelector('#demo-panel').setAttribute('aria-labelledby', tabs[index].id);
    document.querySelector('#chat-example').hidden = terminal;
    document.querySelector('#terminal-example').hidden = !terminal;
    document.querySelector('#composer-mode').textContent = terminal ? 'Cove 原生输入框' : 'Claude Code';
  }
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => selectMode(index));
    tab.addEventListener('keydown', event => {
      if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
      event.preventDefault();
      const next = event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1 : (index + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length;
      selectMode(next);
      tabs[next].focus();
    });
  });
  document.querySelector('#appearance').addEventListener('click', event => {
    const dark = document.querySelector('#app-window').classList.toggle('is-dark');
    event.currentTarget.setAttribute('aria-pressed', String(dark));
    event.currentTarget.textContent = dark ? '预览浅色' : '预览深色';
  });
  document.querySelectorAll('[data-copy]').forEach(button => button.addEventListener('click', async () => {
    const command = button.dataset.copy;
    const status = document.querySelector('#copy-status');
    try {
      await navigator.clipboard.writeText(command);
      button.textContent = '已复制';
      status.textContent = '已复制：' + command + '。请在已检出的开发分支内运行。';
    } catch {
      status.textContent = '请手动复制：' + command;
    }
  }));
})();

(() => {
'use strict';const tabs=[...document.querySelectorAll('[data-feature]')];if(!tabs.length)return;
function select(tab,moveFocus=false){tabs.forEach(item=>{const selected=item===tab;item.setAttribute('aria-selected',String(selected));item.tabIndex=selected?0:-1;const panel=document.getElementById(item.getAttribute('aria-controls'));if(panel)panel.hidden=!selected;});if(moveFocus)tab.focus();}
tabs.forEach((tab,index)=>{tab.addEventListener('click',()=>select(tab));tab.addEventListener('keydown',event=>{let next;if(event.key==='ArrowRight')next=(index+1)%tabs.length;else if(event.key==='ArrowLeft')next=(index-1+tabs.length)%tabs.length;else if(event.key==='Home')next=0;else if(event.key==='End')next=tabs.length-1;else return;event.preventDefault();select(tabs[next],true);});});
})();
