import { Routes } from '@angular/router';
import { QueueComponent } from './pages/queue/queue.component';
import { ReviewComponent } from './pages/review/review.component';

export const routes: Routes = [
  { path: '', redirectTo: 'queue', pathMatch: 'full' },
  { path: 'queue', component: QueueComponent },
  { path: 'applications/:id/review', component: ReviewComponent },
];
