import { Component } from '@angular/core';
import { RouterLink, RouterOutlet } from '@angular/router';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, RouterLink],
  template: `
    <div class="nb-shell">
      <header class="nb-header">
        <a routerLink="/queue" class="nb-brand">
          <svg class="nb-brand-mark" viewBox="0 0 32 32" fill="none" aria-hidden="true">
            <path d="M4 23V15Q16 4 28 15V23" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" />
            <path d="M4 23V27M28 23V27M2 27H30" stroke="currentColor" stroke-width="3" stroke-linecap="round" />
          </svg>
          <span class="nb-brand-text">
            <span class="nb-brand-name">Northbridge Lending</span>
            <span class="nb-brand-app">Reviewer Console</span>
          </span>
        </a>
        <nav class="nb-nav-links">
          <a routerLink="/queue">Queue</a>
        </nav>
      </header>
      <main class="nb-main">
        <router-outlet></router-outlet>
      </main>
    </div>
  `,
})
export class AppComponent {}
