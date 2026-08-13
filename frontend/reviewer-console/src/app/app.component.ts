import { Component } from '@angular/core';
import { RouterLink, RouterOutlet } from '@angular/router';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, RouterLink],
  template: `
    <nav>
      <a routerLink="/queue">Northbridge Lending — Reviewer Console</a>
    </nav>
    <router-outlet></router-outlet>
  `,
})
export class AppComponent {}
